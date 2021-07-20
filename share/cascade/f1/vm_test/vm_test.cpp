#include <unistd.h>
#include <stdio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <signal.h>
#include <sys/mman.h>
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <cstdlib>
#include <vector>
#include <chrono>
#include <thread>
#include <algorithm>

pci_bar_handle_t sys_bar_handle;
pci_bar_handle_t dram_bar_handle;

std::vector<uint64_t> *vm_map;

volatile bool running = true;
void handler(int signal) {
    if (running) {
        running = false;
    } else {
        exit(EXIT_FAILURE);
    }
}

void do_io(int fd, bool writing, uint64_t buffer_size, uint64_t xfer_size, uint64_t offset) {
    // Allocate page-aligned buffers for data transfer
    void* buffer_ptr = aligned_alloc(1<<12, buffer_size);
    if (buffer_ptr == nullptr) {
        printf("Could not allocate buffer\n");
        exit(EXIT_FAILURE);
    }
    
    while (xfer_size > 0) {
        uint64_t count = (xfer_size < buffer_size) ? xfer_size : buffer_size;
        int64_t nbytes = 0;
        if (writing) nbytes = pwrite(fd, buffer_ptr, count, offset);
        else         nbytes = pread (fd, buffer_ptr, count, offset);
        if (nbytes == -1) {
            printf("pread/pwrite transaction failed with error \"%s\"\n", strerror(errno));
            printf("%d, %d, %p, %lu, %lu\n", writing, fd, buffer_ptr, count, offset);
            exit(EXIT_FAILURE);
        }
        if (nbytes == 0) printf("pread/pwrite transferred no data\n");
        if (nbytes > (int64_t)xfer_size) printf("bad nbytes\n");
        xfer_size -= nbytes;
        offset += nbytes;
    }
    
    free(buffer_ptr);
}

int main(void) {
    const uint64_t num_apps = 4;
    const bool send_data = true;
    const bool nvme_file = false;
    const bool timing = false;
    int rc;
    
    signal(SIGINT, handler);
    
    // Open XDMA device files
    int dth_fd[4];
    dth_fd[0] = open("/dev/xdma0_c2h_0", O_RDONLY);
    dth_fd[1] = open("/dev/xdma0_c2h_1", O_RDONLY);
    dth_fd[2] = open("/dev/xdma0_c2h_2", O_RDONLY);
    dth_fd[3] = open("/dev/xdma0_c2h_3", O_RDONLY);
    if (dth_fd[3] == -1) {
        printf("Could not open XDMA C2H device\n");
        exit(EXIT_FAILURE);
    }
    int htd_fd[4];
    htd_fd[0] = open("/dev/xdma0_h2c_0", O_WRONLY);
    htd_fd[1] = open("/dev/xdma0_h2c_1", O_WRONLY);
    htd_fd[2] = open("/dev/xdma0_h2c_2", O_WRONLY);
    htd_fd[3] = open("/dev/xdma0_h2c_3", O_WRONLY);
    if (htd_fd[3] == -1) {
        printf("Could not open XDMA H2C device\n");
        exit(EXIT_FAILURE);
    }
    printf("XDMA devices opened\n");
    
    // Open NVME files
    int nvme_fd[4];
    if (nvme_file) {
        nvme_fd[0] = open("/mnt/nvme0/file0.bin", O_RDWR);
        nvme_fd[1] = open("/mnt/nvme0/file1.bin", O_RDWR);
        nvme_fd[2] = open("/mnt/nvme0/file2.bin", O_RDWR);
        nvme_fd[3] = open("/mnt/nvme0/file3.bin", O_RDWR);
        if (nvme_fd[3] == -1) {
            printf("Could not open NVME file\n");
            exit(EXIT_FAILURE);
        }
        printf("NVME files opened\n");
    }
    
    // Map BARs
    rc = fpga_mgmt_init();
    if (rc) printf("FPGA mgmt init failure\n");
    rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR1, 0, &sys_bar_handle);
    if (rc) printf("System BAR attach failure\n");
    rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR4, BURST_CAPABLE, &dram_bar_handle);
    if (rc) printf("DRAM BAR attach failure\n");
    printf("BARs mapped\n");
    
    // Zero device
    if (send_data) do_io(htd_fd[0], true, (64<<20), (uint64_t{512}<<20), (uint64_t{0}<<30));
    else do_io(htd_fd[0], true, (64<<20), (uint64_t{64}<<30), (uint64_t{0}<<30));
    /*
    std::thread t0(do_io, htd_fd[0], true, (64<<20), (uint64_t{16}<<30), (uint64_t{0}<<30));
    std::thread t1(do_io, htd_fd[1], true, (64<<20), (uint64_t{16}<<30), (uint64_t{16}<<30));
    std::thread t2(do_io, htd_fd[2], true, (64<<20), (uint64_t{16}<<30), (uint64_t{32}<<30));
    std::thread t3(do_io, htd_fd[3], true, (64<<20), (uint64_t{16}<<30), (uint64_t{48}<<30));
    t0.join();
    t1.join();
    t2.join();
    t3.join();
    */
    printf("FPGA DRAM zeroed\n");
    
    // Allocate mapping table
    vm_map = new std::vector<uint64_t>[num_apps];
    for (uint64_t i = 0; i < num_apps; ++i) {
        vm_map[i].resize(16<<20, 0);
    }
    printf("VM map allocated\n");
    
    // Allocate transfer buffer
    uint64_t *xfer_buf = (uint64_t*)aligned_alloc(1<<12, 1<<12);
    printf("DMA buffer(s) allocated\n");
    
    // Handle VM requests
    printf("Ready\n");
    while (running) {
        for (uint64_t app = 0; app < num_apps; ++app) {
            const uint64_t reg_addr = app*0x8;
            uint64_t req, resp, entry, nbytes;
            for (uint64_t i = 0; i < 32; ++i) {
                std::chrono::high_resolution_clock::time_point start = std::chrono::high_resolution_clock::now();
                
                // Get request
                fpga_pci_peek64(sys_bar_handle, reg_addr, &req);
                if (!~req || !(req&0x1)) break;
                
                // Decode
                //const bool reading = (req >> 1) & 0x1;
                const uint64_t vpn = req >> 2;
                const bool rw = true;
                const uint64_t ppn = vpn + (128<<10);
                resp = (ppn << 1) + 0x1;
                
                // Return early if entry already valid
                entry = vm_map[app][vpn];
                if (entry != 0) {
                    fpga_pci_poke64(sys_bar_handle, reg_addr, resp);
                    continue;
                }
                
                // Get page data
                if (nvme_file) {
                    nbytes = pread(nvme_fd[app], (void*)xfer_buf, 4<<10, vpn << 12);
                    if (nbytes != (4<<10)) {
                        printf("NVME page read failed with error \"%s\"\n", strerror(errno));
                        exit(EXIT_FAILURE);
                    }
                }
                
                // Do transfer
                if (send_data) {
                    //fpga_pci_write_burst(dram_bar_handle, ppn << 12, (uint32_t*)xfer_buf, (1<<10));
                    nbytes = pwrite(htd_fd[0], xfer_buf, (4<<10), ppn << 12);
                    if (nbytes != (4<<10)) {
                        printf("DRAM page write failed with error \"%s\"\n", strerror(errno));
                        exit(EXIT_FAILURE);
                    }
                }
                
                // Update page entry
                /*
                entry = 0;
                entry |= app;
                entry <<= 36;
                entry |= vpn;
                entry <<= 24;
                entry |= ppn;
                entry <<= 1;
                entry |= uint64_t{rw};
                entry <<= 1;
                entry |= 0x1ull;
                */
                entry = (app << 62) | (vpn << 26) | (ppn << 2) | (rw << 1) | 0x1;
                vm_map[app][vpn] = entry;
                bool upper_half = vpn & (1<<23);
                uint64_t dram_addr = (vpn&0x7FFFFF)*64 + app*16 + upper_half*8;
                fpga_pci_poke64(dram_bar_handle, dram_addr, entry);
                fpga_pci_poke64(sys_bar_handle, reg_addr, resp);
                
                std::chrono::high_resolution_clock::time_point end = std::chrono::high_resolution_clock::now();
                
                // Debug
                //printf("%p -> %p @ %p\n", vpn << 12, ppn << 12, dram_addr);
                //printf("0x%lX\n", entry);
                if (timing) {
                    std::chrono::duration<double> diff = end - start;
                    double seconds = diff.count();
                    printf("handling request took %g seconds\n", seconds);
                }
            }
        }
    }
    printf("Done handling requests\n");
    
    rc = fpga_pci_detach(dram_bar_handle);
    if (rc) printf("DRAM BAR detatch failure\n");
    rc = fpga_pci_detach(sys_bar_handle);
    if (rc) printf("Sys BAR detatch failure\n");
    
    if (nvme_file) {
        close(nvme_fd[0]);
        close(nvme_fd[1]);
        close(nvme_fd[2]);
        close(nvme_fd[3]);
    }
    close(dth_fd[0]);
    close(dth_fd[1]);
    close(dth_fd[2]);
    close(dth_fd[3]);
    close(htd_fd[0]);
    close(htd_fd[1]);
    close(htd_fd[2]);
    close(htd_fd[3]);
    
    return 0;
}
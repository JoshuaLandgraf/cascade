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

const uint64_t num_apps = 4;
const bool send_data = true;
const bool nvme_file = true;
const bool mmap_io = false;
const bool prefetch = true;

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

class AddrPrefetchHelper {
    std::vector<uint64_t> vpns;
    std::vector<uint64_t> lens;
    std::vector<uint64_t> ages;
    uint64_t max_len;
    
public:
    AddrPrefetchHelper (uint64_t entries, uint64_t max_len) {
        vpns.resize(entries, -1);
        lens.resize(entries, 1);
        ages.resize(entries);
        for (uint64_t i = 0; i < entries; ++i) {
            ages[i] = entries - i - 1;
        }
        this->max_len = max_len;
    }
    
    uint64_t get_num_pages(uint64_t vpn) {
        // increment LRU age and find oldest entry
        uint64_t idx = 0;
        for (uint64_t i = 1; i < ages.size(); ++i) {
            if (ages[i] > ages[idx]) idx = i;
            ++ages[i];
        }
        // search for match
        for (uint64_t i = 0; i < vpns.size(); ++i) {
            if (vpn == vpns[i]) {
                lens[i] = std::min(2*lens[i], max_len);
                vpns[i] += lens[i];
                ages[i] = 0;
                return lens[i];
            }
        }
        // no match, replace oldest entry
        vpns[idx] = vpn + 1;
        lens[idx] = 1;
        ages[idx] = 0;
        return 1;
    }
};

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

void handle_reqs(int htd_fd, int nvme_fd, void* nvme_ptr, uint64_t app) {
    const uint64_t reg_addr = app*0x8;
    uint64_t req, resp, entry, nbytes;

    // Allocate transfer buffer
    uint64_t *xfer_buf = (uint64_t*)aligned_alloc(1<<12, 2<<20);
    
    // Create 
    AddrPrefetchHelper aph(8, 512);
    
    while (running) {
        // Get request
        fpga_pci_peek64(sys_bar_handle, reg_addr, &req);
        if (!~req || !(req&0x1)) {
            usleep(20);
            continue;
        }
        
        // Decode
        //const bool reading = (req >> 1) & 0x1;
        const uint64_t base_vpn = req >> 2;
        const bool rw = true;
        const uint64_t base_ppn = base_vpn + (128<<10);
        resp = (base_ppn << 1) + 0x1;
        
        // Return early if entry already valid
        entry = vm_map[app][base_vpn];
        if (entry != 0) {
            fpga_pci_poke64(sys_bar_handle, reg_addr, resp);
            continue;
        }
        
        uint64_t num_pages = prefetch ? aph.get_num_pages(base_vpn) : 1;
        for (uint64_t vpn = base_vpn + 1; prefetch && (vpn < base_vpn + num_pages); ++vpn) {
            entry = vm_map[app][vpn];
            if (entry != 0) {
                num_pages = 1;
                break;
            }
        }
        //printf("vpn %lu : %lu pages\n", base_vpn, num_pages);
        
        // Get page data
        if (nvme_file && !mmap_io) {
            nbytes = pread(nvme_fd, (void*)xfer_buf, num_pages<<12, base_vpn << 12);
            if (nbytes != (num_pages<<12)) {
                printf("NVME page read failed with error \"%s\"\n", strerror(errno));
                exit(EXIT_FAILURE);
            }
        }
        
        // Do transfer
        if (send_data) {
            void* buf_ptr;
            if (nvme_file && mmap_io) {
                buf_ptr = (void*)(((char*)nvme_ptr) + (base_vpn << 12));
            } else {
                buf_ptr = xfer_buf;
            }
            
            //fpga_pci_write_burst(dram_bar_handle, base_ppn << 12, (uint32_t*)xfer_buf, (num_pages<<10));
            
            nbytes = pwrite(htd_fd, buf_ptr, (num_pages<<12), base_ppn << 12);
            if (nbytes != (num_pages<<12)) {
                printf("DRAM page write failed with error \"%s\"\n", strerror(errno));
                exit(EXIT_FAILURE);
            }
        }
        
        // Update page entry / entries
        for (uint64_t vpn = base_vpn; vpn < base_vpn + num_pages; ++vpn) {
            const uint64_t ppn = vpn + (128<<10);
            entry = (app << 62) | (vpn << 26) | (ppn << 2) | (rw << 1) | 0x1;
            vm_map[app][vpn] = entry;
            bool upper_half = vpn & (1<<23);
            uint64_t dram_addr = (vpn&0x7FFFFF)*64 + app*16 + upper_half*8;
            fpga_pci_poke64(dram_bar_handle, dram_addr, entry);
        }
        
        // Send response
        fpga_pci_poke64(sys_bar_handle, reg_addr, resp);
    }
    
    free(xfer_buf);
    printf("Thread done\n");
}

int main(void) {
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
    
    // MMAP NVME files
    void* nvme_ptr[4];
    size_t nvme_len[4];
    if (nvme_file && mmap_io) {
        for (int i = 0; i < 4; ++i) {
            struct stat st;
            fstat(nvme_fd[i], &st);
            nvme_len[i] = st.st_size;
            nvme_ptr[i] = mmap(NULL, nvme_len[i], PROT_READ|PROT_WRITE, MAP_SHARED, nvme_fd[i], 0);
            if (!nvme_ptr[i]) {
                printf("Could not map NVME file %d\n", i);
                exit(EXIT_FAILURE);
            }
        }
        printf("NVME files MMAPed\n");
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
    if (send_data) {
        do_io(htd_fd[0], true, (64<<20), (uint64_t{512}<<20), (uint64_t{0}<<30));
    } else {
        //do_io(htd_fd[0], true, (64<<20), (uint64_t{64}<<30), (uint64_t{0}<<30));
        std::thread t0(do_io, htd_fd[0], true, (64<<20), (uint64_t{16}<<30), (uint64_t{0}<<30));
        std::thread t1(do_io, htd_fd[1], true, (64<<20), (uint64_t{16}<<30), (uint64_t{16}<<30));
        std::thread t2(do_io, htd_fd[2], true, (64<<20), (uint64_t{16}<<30), (uint64_t{32}<<30));
        std::thread t3(do_io, htd_fd[3], true, (64<<20), (uint64_t{16}<<30), (uint64_t{48}<<30));
        t0.join();
        t1.join();
        t2.join();
        t3.join();
    }
    printf("FPGA DRAM zeroed\n");
    
    // Allocate mapping table
    vm_map = new std::vector<uint64_t>[num_apps];
    for (uint64_t i = 0; i < num_apps; ++i) {
        vm_map[i].resize(16<<20, 0);
    }
    printf("VM map allocated\n");
    
    // Handle VM requests
    std::vector<std::thread> threads;
    for (uint64_t app = 0; app < num_apps; ++app) {
        threads.push_back(std::thread(handle_reqs, htd_fd[app], nvme_fd[app], nvme_ptr[app], app));
    }
    printf("Ready\n");
    
    for (uint64_t app = 0; app < num_apps; ++app) {
        threads[app].join();
    }
    printf("Done handling requests\n");
    
    // Clean up
    rc = fpga_pci_detach(dram_bar_handle);
    if (rc) printf("DRAM BAR detatch failure\n");
    rc = fpga_pci_detach(sys_bar_handle);
    if (rc) printf("Sys BAR detatch failure\n");
    
    if (nvme_file && mmap_io) {
        for (int i = 0; i < 4; ++i) {
            munmap(nvme_ptr[i], nvme_len[i]);
        }
    }
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

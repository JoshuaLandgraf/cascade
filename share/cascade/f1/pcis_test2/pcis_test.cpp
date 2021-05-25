#include <unistd.h>
#include <stdio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <sys/mman.h>
#include <cstdlib>
#include <vector>
#include <chrono>
#include <thread>
#include <algorithm>
#include <fpga_mgmt.h>
#include <fpga_pci.h>

void do_io(pci_bar_handle_t pci_bar_handle, bool writing, uint64_t buffer_size, uint64_t xfer_size, uint64_t offset) {
    // Allocate page-aligned buffers for data transfer
    uint32_t* buffer_ptr = (uint32_t*)aligned_alloc(1<<12, buffer_size);
    if (buffer_ptr == nullptr) {
        printf("Could not allocate buffer\n");
        exit(EXIT_FAILURE);
    }
    
    while (xfer_size > 0) {
        uint64_t count = (xfer_size < buffer_size) ? xfer_size : buffer_size;
        int rc = 0;
        if (writing) rc = fpga_pci_write_burst(pci_bar_handle, offset, buffer_ptr, count/4);
        else         rc = fpga_pci_poke64(pci_bar_handle, offset, buffer_ptr[(offset/4) % buffer_size]);
        if (rc != 0) {
            printf("read/write transaction failed\n");
            exit(EXIT_FAILURE);
        }
        xfer_size -= (writing ? count : 8);
        offset += (writing ? count : 8);
    }
    
    free(buffer_ptr);
}

int main(void) {
    uint64_t num_threads = 1;
    
    pci_bar_handle_t pci_bar_handle;
    int rc = 0;
    rc |= fpga_mgmt_init();
    rc |= fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR4, 0, &pci_bar_handle);
    //rc |= fpga_pci_memset(pci_bar_handle, 0, 0, uint64_t{16}<<30);
    if (rc) {
        printf("Initialization failure 3\n");
        exit(EXIT_FAILURE);
    }
    
    std::vector<std::thread> threads;
    int num_modes = (num_threads > 1) ? 3 : 2;
    for (int i = 0; i < num_modes; ++i) {
        bool reading = (i == 0) || (i == 2);
        bool writing = (i == 1) || (i == 2);
        
        for (uint64_t xfer_size = 512; xfer_size <= (1<<22); xfer_size *= 2) {
            uint64_t total_xfer = std::min(xfer_size * (1<<13), (uint64_t{64}<<30));
            uint64_t thread_bytes = total_xfer / num_threads;
            threads.reserve(num_threads);
            
            auto start = std::chrono::high_resolution_clock::now();
            for (uint64_t thread = 0; thread < num_threads; ++thread) {
                bool thread_writing = writing && !(reading && (thread < (num_threads/2)));
                uint64_t thread_offset = thread*(uint64_t{64}<<30)/num_threads;
                threads.emplace_back(do_io, pci_bar_handle, thread_writing, xfer_size, thread_bytes, thread_offset);
            }
            for (uint64_t thread = 0; thread < num_threads; ++thread) {
                threads[thread].join();
            }
            auto end = std::chrono::high_resolution_clock::now();
            threads.clear();
            
            std::chrono::duration<double> seconds = end-start;
            printf("%s %lu bytes with %lu threads and %lu byte xfers took %g seconds: %g MiB/s\n",
                (reading && writing ? "RWing" : (writing ? "Writing" : "Reading")), total_xfer,
                num_threads, xfer_size, seconds.count(), ((double)total_xfer)/seconds.count()/(1<<20));
        }
    }
    
    fpga_pci_detach(pci_bar_handle);
    
    return 0;
}

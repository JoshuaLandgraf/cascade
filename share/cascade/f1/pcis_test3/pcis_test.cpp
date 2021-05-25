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
    uint64_t num_threads = 4;
    
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
    
    // Zero device
    do_io(htd_fd[0], true, (2<<20), (uint64_t{64}<<30), (uint64_t{0}<<30));
    return 0;
    
    std::vector<std::thread> threads;
    int num_modes = (num_threads > 1) ? 3 : 2;
    for (int i = 0; i < num_modes; ++i) {
        bool reading = (i == 0) || (i == 2);
        bool writing = (i == 1) || (i == 2);
        
        for (uint64_t xfer_size = 512; xfer_size <= (1<<22); xfer_size *= 2) {
            uint64_t total_xfer = std::min(xfer_size * (1<<17), (uint64_t{64}<<30));
            uint64_t thread_bytes = total_xfer / num_threads;
            threads.reserve(num_threads);
            
            auto start = std::chrono::high_resolution_clock::now();
            for (uint64_t thread = 0; thread < num_threads; ++thread) {
                bool thread_writing = writing && !(reading && (thread < (num_threads/2)));
                int thread_fd = thread_writing ? htd_fd[thread] : dth_fd[thread];
                uint64_t thread_offset = thread*(uint64_t{64}<<30)/num_threads;
                threads.emplace_back(do_io, thread_fd, thread_writing, xfer_size, thread_bytes, thread_offset);
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

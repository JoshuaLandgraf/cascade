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
    do_io(htd_fd[0], true, (64<<20), (uint64_t{64}<<30), (uint64_t{0}<<30));
    printf("Device zeroed\n");
    
    // Allocate table buffer
    uint64_t *vm_buf = (uint64_t*)aligned_alloc(1<<12, 1<<29);
    
    // Init first 8 entries
    vm_buf[0] = 3;
    vm_buf[0] |= 1<<(29-12+2);
    vm_buf[1] = vm_buf[0];
    vm_buf[1] |= 1<<(35-12+2);
    vm_buf[1] |= uint64_t{1}<<(35-12+26);
    vm_buf[2] = vm_buf[0] | (uint64_t{1}<<62);
    vm_buf[3] = vm_buf[1] | (uint64_t{1}<<62);
    vm_buf[4] = vm_buf[0] | (uint64_t{2}<<62);
    vm_buf[5] = vm_buf[1] | (uint64_t{2}<<62);
    vm_buf[6] = vm_buf[0] | (uint64_t{3}<<62);
    vm_buf[7] = vm_buf[1] | (uint64_t{3}<<62);
    
    /*
    uint8_t *byte_buf = (uint8_t*)vm_buf;
    uint8_t temp = byte_buf[0];
    byte_buf[0] = byte_buf[7];
    byte_buf[7] = temp;
    temp = byte_buf[1];
    byte_buf[1] = byte_buf[6];
    byte_buf[6] = temp;
    temp = byte_buf[2];
    byte_buf[2] = byte_buf[5];
    byte_buf[5] = temp;
    temp = byte_buf[3];
    byte_buf[3] = byte_buf[4];
    byte_buf[4] = temp;
    */
    
    // Loop over other entries
    for (uint64_t i = 8; i < (1<<(29-3)); i += 8) {
        vm_buf[i] = vm_buf[i-8];
        vm_buf[i] += 1<<2;
        vm_buf[i] += 1<<26;
        vm_buf[i+1] = vm_buf[i-7];
        if (i >= ((1<<(29-3))-(1<<(29-12+3)))) {
            vm_buf[i+1] &= 0xFFFFFFFFFFFFFFFE;
            //printf("0x%lx\n", vm_buf[i+1]);
        } else {
            vm_buf[i+1] += 1<<2;
        }
        vm_buf[i+1] += 1<<26;
        vm_buf[i+2] = vm_buf[i]   | (uint64_t{1}<<62);
        vm_buf[i+3] = vm_buf[i+1] | (uint64_t{1}<<62);
        vm_buf[i+4] = vm_buf[i]   | (uint64_t{2}<<62);
        vm_buf[i+5] = vm_buf[i+1] | (uint64_t{2}<<62);
        vm_buf[i+6] = vm_buf[i]   | (uint64_t{3}<<62);
        vm_buf[i+7] = vm_buf[i+1] | (uint64_t{3}<<62);
    }
    
    // Transfer to device
    int rc = pwrite(htd_fd[0], vm_buf, 1<<29, 0);
    if (rc != (1<<29)) printf("VM pwrite error: %d\n", rc);
    
    /*
    for (uint64_t i = 0; i < (1<<29); i += (2<<20)) {
        int rc = pwrite(htd_fd[0], vm_buf + (i/8), 2<<20, i);
        if (rc) printf("VM prwite error on %lu: %d\n", i, rc);
    }*/
    
    printf("VM table initialized\n");
    
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

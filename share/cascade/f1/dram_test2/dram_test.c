#include <stdio.h>
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <vector>
#include <chrono>

using namespace std::chrono;

const uint16_t pci_vendor_id = 0x1D0F;
const uint16_t pci_device_id = 0xF001;

pci_bar_handle_t pci_bar_handle;

uint64_t to_command(uint64_t phys_addr, uint64_t length, uint64_t id) {
    uint64_t command = (phys_addr >> 6) << 28;
    command |= ((length/64)-1) << 8;
    command |= id;
    return command;
}

void start_access(bool write, uint64_t phys_addr, uint64_t length, uint64_t id, uint64_t src) {
    uint64_t cmd = to_command(phys_addr, length, id);
    uint64_t reg_addr = 0x10*src + (write ? 0x8 : 0x0);
    int rc = fpga_pci_poke64(pci_bar_handle, reg_addr, cmd);
    if (rc) printf("Poke failure\n");
}

void finish_accesses(bool write, uint64_t num, uint64_t src) {
    const bool printing = false;
    for (uint64_t i = 0; i < num; ) {
        uint64_t id_vector;
        uint64_t reg_addr =	0x10*src + (write ? 0x8 : 0x0);
        int rc = fpga_pci_peek64(pci_bar_handle, reg_addr, &id_vector);
        if (rc) printf("Peek failure\n");
        if (printing) printf("%lu\n", id_vector);
        for (uint64_t j = 0; j < 8; ++j) {
            if ((id_vector >> (7+8*j)) & 1) {
                ++i;
                if (printing && (j == 7)) printf("8\n");
                if ((id_vector >> (5+8*j)) & 0x3) printf("Bad response: 0x%lx\n", ((id_vector >> (5+8*j)) & 0x3));
            } else {
                if (printing) printf("%lu\n", j);
                break;
            }
        }
    }
}

int main(void) {
    int rc;
    //pci_bar_handle_t pci_bar_handle = PCI_BAR_HANDLE_INIT;
    
    rc = fpga_mgmt_init();
    if (rc) printf("Init failure\n");
    rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR1, 0, &pci_bar_handle);
    if (rc) printf("Attach failure\n");
    
    // zero FPGA
    /*
    for (uint64_t i = 0; i < uint64_t{64}<<30; ) {
        for (uint64_t j = 0; j < 32; ++j) {
            start_access(true, i, 1<<20, j, 0);
            i += 1<<20;
        }
        finish_accesses(true, 32, 0);
    }*/

    const uint64_t count = 32;
    const bool ordered = true;
    
    // single source, single dest
    printf("Single source, single dest test\n");
    for (int i = 0; i < 3; ++i) {
        bool reading = (i == 0) || (i == 2);
        bool writing = (i == 1) || (i == 2);
        if (i == 0) printf("Reading test\n");
        if (i == 1) printf("Writing test\n");
        if (i == 2) printf("Reading and writing test\n");
        
        for (uint64_t stride = 512; stride <= (1<<20); stride *= 2) {
            high_resolution_clock::time_point start = high_resolution_clock::now();
            for (uint64_t j = 0; j < count; ++j) {
                if (reading) start_access(false, j*stride, stride, (ordered ? 0 : j), 0);
                if (writing) start_access(true,  (uint64_t{1}<<30)+j*stride, stride, (ordered ? 0 : j), 0);
            }
            if (reading) finish_accesses(false, count, 0);
            if (writing) finish_accesses(true, count, 0);
            high_resolution_clock::time_point end = high_resolution_clock::now();
            
            duration<double> diff = end - start;
            double seconds = diff.count();
            uint64_t total_count = count * (reading && writing ? 2 : 1);
            uint64_t total_bytes = count * stride * (reading && writing ? 2 : 1);
            printf("%lu x %lu bytes in %g seconds for %g MiB/s\n", total_count, stride, seconds, ((double)total_bytes)/seconds/(1<<20));
        }
    }

    // single source, multi dest
    printf("Single source, multi dest test\n");
    for (int i = 0; i < 3; ++i) {
        bool reading = (i == 0) || (i == 2);
        bool writing = (i == 1) || (i == 2);
        if (i == 0) printf("Reading test\n");
        if (i == 1) printf("Writing test\n");
        if (i == 2) printf("Reading and writing test\n");
        
        for (uint64_t stride = 512; stride <= (1<<20); stride *= 2) {
            high_resolution_clock::time_point start = high_resolution_clock::now();
            for (uint64_t j = 0; j < count; ++j) {
                if (reading) start_access(false, (j*stride)+(j%4)*16*(1<<30), stride, (ordered ? 0 : j), 0);
                if (writing) start_access(true,  (1<<30)+(j*stride)+((j+1)%4)*16*(1<<30), stride, (ordered ? 0 : j), 0);
            }
            if (reading) finish_accesses(false, count, 0);
            if (writing) finish_accesses(true, count, 0);
            high_resolution_clock::time_point end = high_resolution_clock::now();
            
            duration<double> diff = end - start;
            double seconds = diff.count();
            uint64_t total_count = count * (reading && writing ? 2 : 1);
            uint64_t total_bytes = count * stride * (reading && writing ? 2 : 1);
            printf("%lu x %lu bytes in %g seconds for %g MiB/s\n", total_count, stride, seconds, ((double)total_bytes)/seconds/(1<<20));
        }
    }
    
    // multi source, multi dest
    printf("Single source, multi dest test\n");
    for (int i = 0; i < 3; ++i) {
        bool reading = (i == 0) || (i == 2);
        bool writing = (i == 1) || (i == 2);
        if (i == 0) printf("Reading test\n");
        if (i == 1) printf("Writing test\n");
        if (i == 2) printf("Reading and writing test\n");
        
        for (uint64_t stride = 512; stride <= (1<<20); stride *= 2) {
            high_resolution_clock::time_point start = high_resolution_clock::now();
            for (uint64_t j = 0; j < count; ++j) {
                if (reading) start_access(false, (j*stride)+(j%4)*16*(1<<30), stride, (ordered ? 0 : j), j%4);
                if (writing) start_access(true,  (1<<30)+(j*stride)+((j+1)%4)*16*(1<<30), stride, (ordered ? 0 : j), j%4);
            }
            for (uint64_t j = 0; j < 4; ++j) {
                if (reading) finish_accesses(false, count/4, j);
                if (writing) finish_accesses(true,  count/4, j);
            }
            high_resolution_clock::time_point end = high_resolution_clock::now();
            
            duration<double> diff = end - start;
            double seconds = diff.count();
            uint64_t total_count = count * (reading && writing ? 2 : 1);
            uint64_t total_bytes = count * stride * (reading && writing ? 2 : 1);
            printf("%lu x %lu bytes in %g seconds for %g MiB/s\n", total_count, stride, seconds, ((double)total_bytes)/seconds/(1<<20));
        }
    }
    
    rc = fpga_pci_detach(pci_bar_handle);
    if (rc) printf("Detach failure\n");
    return 0;
}

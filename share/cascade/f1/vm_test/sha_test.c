#include <stdio.h>
#include <unistd.h>
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <vector>
#include <chrono>

using namespace std::chrono;

pci_bar_handle_t pci_bar_handle;

struct test_config {
    uint32_t abcdefgh[8];
    uint64_t src_addr;
    uint64_t rd_credits;
    uint64_t num_words;
} test_config;

void start_run(uint64_t src) {
    int rc = 0;
    uint64_t reg_addr = 0x8*src;
    uint64_t reg_inc = 0x800;
    
    reg_addr += reg_inc;
    reg_addr += reg_inc;
    reg_addr += reg_inc;
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.src_addr);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.rd_credits);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.num_words);
    
    if (rc) printf("Poke failure\n");
}

void end_run(uint64_t src, uint64_t words_req) {
    int rc = 0;
    const uint64_t reg_addr = 0x8*src + 0x800*7;
    
    uint64_t words_done = 0;
    while (words_done != words_req) {
        usleep(100);
        rc |= fpga_pci_peek64(pci_bar_handle, reg_addr, &words_done);
        //printf("words left: %lu\n", words_left);
    }
    
    if (rc) printf("Peek failure\n");
}

int main(void) {
    int rc;
    
    rc = fpga_mgmt_init();
    if (rc) printf("Init failure\n");
    rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR0, 0, &pci_bar_handle);
    if (rc) printf("Attach failure\n");
    
    uint64_t src_addrs[4] = {0x0, 0x400000000, 0x200000000, 0x600000000};
    
    const uint64_t total_words_max = (uint64_t{30} << 30) / 64;
    
    test_config.rd_credits = 8;

    for (uint64_t num_inst = 1; num_inst <= 4; num_inst *= 2) {
        uint64_t total_words = (64<<20);
        //for (uint64_t total_words = (2<<20); total_words < total_words_max; total_words *= 2) {
        {
            uint64_t range = total_words / num_inst;
            
            high_resolution_clock::time_point start = high_resolution_clock::now();
            for (uint64_t i = 0; i < num_inst; ++i) {
                //test_config.src_addr = (range*64) * (2*i);
                //test_config.src_addr = (range*64) * (i);
                test_config.src_addr = src_addrs[i];
                test_config.num_words = range;

                //printf("0x%lX %lu\n", test_config.src_addr, test_config.num_words);
                start_run(i);
            }
            for (uint64_t i = 0; i < num_inst; ++i) {
                end_run(i, range);
            }
            high_resolution_clock::time_point end = high_resolution_clock::now();
            
            duration<double> diff = end - start;
            double seconds = diff.count();
            uint64_t total_bytes = total_words * 64;
            printf("%lu sha: %lu bytes in %g seconds for %g MiB/s\n", num_inst, total_bytes, seconds, ((double)total_bytes)/seconds/(1<<20));
        }
        if (num_inst != 4) sleep(15);
    }
    
    rc = fpga_pci_detach(pci_bar_handle);
    if (rc) printf("Detach failure\n");
    return 0;
}

#include <stdio.h>
#include <unistd.h>
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <vector>
#include <chrono>

using namespace std::chrono;

pci_bar_handle_t pci_bar_handle;

struct aes_config {
    uint64_t key[4];
    uint64_t src_addr;
    uint64_t dst_addr;
    uint64_t num_words;
} aes_config;

void start_run(uint64_t src) {
    int rc = 0;
    uint64_t reg_addr = 0x8*src;
    uint64_t reg_inc = 0x800;
    
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.key[0]);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.key[1]);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.key[2]);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.key[3]);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.src_addr);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.dst_addr);
    reg_addr += reg_inc;
    rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, aes_config.num_words);
    
    if (rc) printf("Poke failure\n");
}

void end_run(uint64_t src) {
    int rc = 0;
    const uint64_t reg_addr = 0x8*src + 0x800*7;
    
    uint64_t words_left = 1;
    do {
        usleep(1);
        rc |= fpga_pci_peek64(pci_bar_handle, reg_addr, &words_left);
    } while (words_left > 0);
    
    if (rc) printf("Peek failure\n");
}

int main(void) {
    int rc;
    
    rc = fpga_mgmt_init();
    if (rc) printf("Init failure\n");
    rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR0, 0, &pci_bar_handle);
    if (rc) printf("Attach failure\n");
    
    uint64_t src_addrs[4] = {0x0, 0x400000000, 0x200000000, 0x600000000};
    uint64_t dst_addrs[4] = {0x800000000, 0xC00000000, 0xA00000000, 0xE00000000};
    
    const uint64_t total_words_max = (uint64_t{30} << 30) / 64;
    
    aes_config.key[0] = 1;
    aes_config.key[1] = 2;
    aes_config.key[2] = 3;
    aes_config.key[3] = 4;    

    for (uint64_t num_aes = 4; num_aes <= 4; num_aes *= 2) {
        uint64_t total_words = (2<<20);
        //for (uint64_t total_words = (2<<20); total_words < total_words_max; total_words *= 2) {
        {
            uint64_t range = total_words / num_aes;
            
            high_resolution_clock::time_point start = high_resolution_clock::now();
            for (uint64_t i = 0; i < num_aes; ++i) {
                //aes_config.src_addr = (range*64) * (2*i);
                //aes_config.dst_addr = (range*64) * (2*i+1);
                //aes_config.src_addr = (range*64) * (i);
                //aes_config.dst_addr = (uint64_t{32} << 30) + (range*64) * (i);
                aes_config.src_addr = src_addrs[i];
                aes_config.dst_addr = dst_addrs[i];
                aes_config.num_words = range;
                //printf("0x%lX 0x%lX %lu\n", aes_config.src_addr, aes_config.dst_addr, aes_config.num_words);
                start_run(i);
            }
            for (uint64_t i = 0; i < num_aes; ++i) {
                end_run(i);
            }
            high_resolution_clock::time_point end = high_resolution_clock::now();
            
            duration<double> diff = end - start;
            double seconds = diff.count();
            uint64_t total_bytes = total_words * 64 * 2;
            printf("%lu aes: %lu bytes in %g seconds for %g MiB/s\n", num_aes, total_bytes, seconds, ((double)total_bytes)/seconds/(1<<20));
        }
        sleep(20);
    }
    
    rc = fpga_pci_detach(pci_bar_handle);
    if (rc) printf("Detach failure\n");
    return 0;
}

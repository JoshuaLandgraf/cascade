#include <stdio.h>
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <vector>
#include <chrono>

using namespace std::chrono;

const uint16_t pci_vendor_id = 0x1D0F;
const uint16_t pci_device_id = 0xF001;

uint64_t to_command(uint64_t phys_addr, uint64_t length, uint64_t id) {
    uint64_t command = (phys_addr >> 6) << 28;
    command |= ((length/64)-1) << 8;
    command |= id;
    return command;
}

int main(void) {
    uint64_t phys_addr = 0;
    int rc;
    pci_bar_handle_t pci_bar_handle = PCI_BAR_HANDLE_INIT;
    uint64_t id_vector;
    
    rc = fpga_mgmt_init();
    if (rc) printf("Init failure\n");
    rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR1, 0, &pci_bar_handle);
    if (rc) printf("Attach failure\n");
    
    const uint64_t range = 8*16 << 10;
    const uint64_t stride = 16 << 10;
    std::vector<uint64_t> read_commands, write_commands;
    for (uint64_t i = 0; i < (range/stride); i += 1) {
        read_commands.push_back(to_command(phys_addr+i*stride, stride, 0));
        write_commands.push_back(to_command(phys_addr+range+i*stride, stride, 0));
    }
    
    const bool printing = false;
    high_resolution_clock::time_point start, end;
    uint64_t ns;
    uint64_t num_reads, num_writes;
    
    // Read
    num_reads = 0; num_writes = 0;
    start = high_resolution_clock::now();
    for (uint64_t cmd : read_commands) {
        rc = fpga_pci_poke64(pci_bar_handle, 0x0, cmd);
        ++num_writes;
        if (rc) printf("Poke failure\n");
    }
    for (uint64_t i = 0; i < read_commands.size();) {
        rc = fpga_pci_peek64(pci_bar_handle, 0x0 , &id_vector);
        ++num_reads;
        if (rc) printf("Peek failure\n");
        if (printing) printf("%lu\n", id_vector);
        for (uint64_t j = 0; j < 8; ++j) {
            if ((id_vector >> (7+8*j)) & 1) {
                ++i;
            } else {
                break;
            }
        }
    }
    end = high_resolution_clock::now();
    ns = duration_cast<std::chrono::nanoseconds>(end - start).count();
    printf("Reading took %lu ns, %lu pokes, %lu peeks\n", ns, num_writes, num_reads);
    
    // Write
    num_reads = 0; num_writes = 0;
    start = high_resolution_clock::now();
    for (uint64_t cmd : write_commands) {
        rc = fpga_pci_poke64(pci_bar_handle, 0x8, cmd);
        ++num_writes;
        if (rc) printf("Poke failure\n");
    }
    for (uint64_t i = 0; i < write_commands.size();) {
        rc = fpga_pci_peek64(pci_bar_handle, 0x8, &id_vector);
        ++num_reads;
        if (rc) printf("Peek failure\n");
        if (printing) printf("%lu\n", id_vector);
        for (uint64_t j = 0; j < 8; ++j) {
            if ((id_vector >> (7+8*j)) & 1) {
                ++i;
            } else {
                break;
            }
        }
    }
    end = high_resolution_clock::now();
    ns = duration_cast<std::chrono::nanoseconds>(end - start).count();
    printf("Writing took %lu ns, %lu pokes, %lu peeks\n", ns, num_writes, num_reads);
    
    // Copy
    const uint64_t times = 1;
    num_reads = 0; num_writes = 0;
    start = high_resolution_clock::now();
    for (uint64_t t = 0; t < times; ++t) {
        for (uint64_t cmd : read_commands) {
            rc = fpga_pci_poke64(pci_bar_handle, 0x0, cmd);
            ++num_writes;
            if (rc) printf("Poke failure\n");
        }
        for (uint64_t cmd : write_commands) {
            rc = fpga_pci_poke64(pci_bar_handle, 0x8, cmd);
            ++num_writes;
            if (rc) printf("Poke failure\n");
        }
    }
    for (uint64_t t = 0; t < times; ++t) {
        for (uint64_t i = 0; i < read_commands.size();) {
            rc = fpga_pci_peek64(pci_bar_handle, 0x0 , &id_vector);
            ++num_reads;
            if (rc) printf("Peek failure\n");
            if (printing) printf("%lu\n", id_vector);
            for (uint64_t j = 0; j < 8; ++j) {
                if ((id_vector >> (7+8*j)) & 1) {
                    ++i;
                } else {
                    break;
                }
            }
        }
        for (uint64_t i = 0; i < write_commands.size();) {
            rc = fpga_pci_peek64(pci_bar_handle, 0x8, &id_vector);
            ++num_reads;
            if (rc) printf("Peek failure\n");
            if (printing) printf("%lu\n", id_vector);
            for (uint64_t j = 0; j < 8; ++j) {
                if ((id_vector >> (7+8*j)) & 1) {
                    ++i;
                } else {
                    break;
                }
            }
        }
    }
    end = high_resolution_clock::now();
    ns = duration_cast<std::chrono::nanoseconds>(end - start).count();
    printf("Copying took %lu ns, %lu pokes, %lu peeks\n", ns, num_writes, num_reads);
    
    rc = fpga_pci_detach(pci_bar_handle);
    if (rc) printf("Detach failure\n");
    return 0;
}

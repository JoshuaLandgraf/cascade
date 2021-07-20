#include <stdio.h>
#include <unistd.h>
#include <fpga_pci.h>
#include <fpga_mgmt.h>

pci_bar_handle_t pci_bar_handle;

struct test_config {
	uint64_t start_addr0;
	uint64_t total_subs;
	uint64_t mask;
	uint64_t mode;
	uint64_t start_addr1;
	uint64_t addr_delta;
	uint64_t canary0;
	uint64_t canary1;
} test_config;

void start_run(uint64_t src) {
	int rc = 0;
	uint64_t reg_addr = 0x8*src;
	uint64_t reg_inc = 0x800;
	
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.start_addr0);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.total_subs);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.mask);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.mode);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.start_addr1);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.addr_delta);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.canary0);
	reg_addr += reg_inc;
	rc |= fpga_pci_poke64(pci_bar_handle, reg_addr, test_config.canary1);
	
	if (rc) printf("Poke failure\n");
}

void end_run(uint64_t src) {
	int rc = 0;
	uint64_t reg_addr = 0x8*src;
	uint64_t reg_inc = 0x800;
	
	// Read back runtime
	uint64_t start_cycle;
	uint64_t end_cycle;
	
	rc |= fpga_pci_peek64(pci_bar_handle, reg_addr, &start_cycle);
	reg_addr += reg_inc;
	rc |= fpga_pci_peek64(pci_bar_handle, reg_addr, &end_cycle);
	
	if (rc) printf("Peek failure\n");
	printf("dnn %lu: %lu cycles (%lu - %lu)\n", src, end_cycle-start_cycle, end_cycle, start_cycle);
}

int main(void) {
	int rc;
	
	rc = fpga_mgmt_init();
	if (rc) printf("Init failure\n");
	rc = fpga_pci_attach(0, FPGA_APP_PF, APP_PF_BAR0, 0, &pci_bar_handle);
	if (rc) printf("Attach failure\n");
	
	// Program Mem Drive
	test_config.start_addr0 = 0x0;
	test_config.total_subs  = 0x15;
	test_config.mask = 0xFFFFFFFFFFFFFFFF;
	test_config.mode = 0x1; // write == 1, read = 0
	test_config.start_addr1 = 0xC000;
	test_config.addr_delta  = 6;
	test_config.canary0     = 0xFEEBFEEBBEEFBEEF;
	test_config.canary1     = 0xDAEDDAEDDEADDEAD;
	
	for (uint64_t num_inst = 1; num_inst <= 4; num_inst *= 2) {
		for (uint64_t i = 0; i < num_inst; ++i) {
			start_run(i);
		}
		usleep(100000);
		for (uint64_t i = 0; i < num_inst; ++i) {
			end_run(i);
		}
		
		if (num_inst != 4) {
			sleep(15);
			printf("\n");
		}
	}
	
	rc = fpga_pci_detach(pci_bar_handle);
	if (rc) printf("Detach failure\n");
	return 0;
}

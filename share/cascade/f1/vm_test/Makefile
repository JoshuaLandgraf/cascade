SDK_DIR = /home/centos/src/project_data/aws-fpga/sdk
HDK_DIR = /home/centos/src/project_data/aws-fpga/hdk

VPATH = src:include:$(HDK_DIR)/common/software/src:$(HDK_DIR)/common/software/include

INCLUDES = -I$(SDK_DIR)/userspace/include
INCLUDES += -I $(HDK_DIR)/common/software/include

CC = g++
CFLAGS = -O3 -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall $(INCLUDES)

LDLIBS = -lfpga_mgmt -lrt -pthread

SRC = ${SDK_DIR}/userspace/utils/sh_dpi_tasks.c

all: vm_test vmt_test dram_test aes_test md5_test sha_test dnn_test

vm_test: vm_test.cpp
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) vm_test.cpp -o vm_test

vmt_test: vmt_test.cpp
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) vmt_test.cpp -o vmt_test

dram_test: dram_test.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) dram_test.c -o dram_test

aes_test: aes_test.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) aes_test.c -o aes_test

md5_test: md5_test.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) md5_test.c -o md5_test

sha_test: sha_test.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) sha_test.c -o sha_test

dnn_test: dnn_test.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) dnn_test.c -o dnn_test

clean:
	rm -f vm_test vmt_test dram_test aes_test md5_test sha_test dnn_test

.PHONY: clean

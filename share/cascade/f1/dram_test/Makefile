VPATH = src:include:$(HDK_DIR)/common/software/src:$(HDK_DIR)/common/software/include

INCLUDES = -I$(SDK_DIR)/userspace/include
INCLUDES += -I $(HDK_DIR)/common/software/include

CC = g++
CFLAGS = -O3 -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall $(INCLUDES)

LDLIBS = -lfpga_mgmt -lrt

SRC = ${SDK_DIR}/userspace/utils/sh_dpi_tasks.c

all: dram

dram: dram_test.c
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) dram_test.c -o dram_test

clean:
	rm -f dram_test

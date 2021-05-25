VPATH = src:include:$(HDK_DIR)/common/software/src:$(HDK_DIR)/common/software/include

INCLUDES = -I$(SDK_DIR)/userspace/include
INCLUDES += -I $(HDK_DIR)/common/software/include

CC = g++
CFLAGS = -O3 -std=c++11 -fpermissive -DCONFIG_LOGLEVEL=4 -g -Wall $(INCLUDES)

LDLIBS = -lfpga_mgmt -lrt -lpthread

SRC = ${SDK_DIR}/userspace/utils/sh_dpi_tasks.c

all: pcis_test

pcis_test: pcis_test.cpp
	$(CC) $(CFLAGS) $(LDFLAGS) $(LDLIBS) $(SRC) pcis_test.cpp -o pcis_test

clean:
	rm -f pcis_test

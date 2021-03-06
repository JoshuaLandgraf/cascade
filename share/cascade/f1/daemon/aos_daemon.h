#include "aos.h"

#include <sys/select.h>
#include <unordered_set>
// FPGA specific includes
#include <fpga_pci.h>
#include <fpga_mgmt.h>
#include <utils/lcd.h>
#include <utils/sh_dpi_tasks.h>

void printError(std::string errStr) {
    std::cout << errStr << std::endl;
}

class aos_host {
public:

    const static uint16_t pci_vendor_id = 0x1D0F; /* Amazon PCI Vendor ID */
    const static uint16_t pci_device_id = 0xF001; /* PCI Device ID preassigned by Amazon for F1 applications */

    aos_host(bool dummy) :
        isDummy(dummy)
    {
        for (int i = 0; i < num_bars; ++i) {
            bar_attached[i]   = false;
            pci_bar_handle[i] = PCI_BAR_HANDLE_INIT;
        }
        // Socket stuff
        memset(&socket_name, 0, sizeof(sockaddr_un));
        socket_name.sun_family = AF_UNIX;
        strncpy(socket_name.sun_path, SOCKET_NAME, sizeof(socket_name.sun_path) - 1);
        socket_initialized = false;
    }

    int init_socket() {
        if (socket_initialized) {
            printf("Socket already intialied");
        }
        passive_socket = socket(SOCKET_FAMILY, SOCKET_TYPE, 0);
        if (passive_socket == -1) {
           perror("socket");
           exit(EXIT_FAILURE);
        }

        int one = 1;
        int ret = setsockopt(passive_socket, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(int));
        if (ret == -1) {
           perror("setsockopt SO_REUSEADDR");
           exit(EXIT_FAILURE);
        }
#ifdef SO_REUSEPORT
        ret = setsockopt(passive_socket, SOL_SOCKET, SO_REUSEPORT, &one, sizeof(int));
        if (ret == -1) {
           perror("setsockopt SO_REUSEPORT");
           exit(EXIT_FAILURE);
        }
#endif
        linger ling;
        ling.l_onoff = 0;
        ling.l_linger = 0;
        ret = setsockopt(passive_socket, SOL_SOCKET, SO_LINGER, &ling, sizeof(linger));
        if (ret == -1) {
           perror("setsockopt SO_LINGER");
           exit(EXIT_FAILURE);
        }

        ret = bind(passive_socket, (const sockaddr *) &socket_name, sizeof( sockaddr_un));
        if (ret == -1) {
           perror("bind");
           exit(EXIT_FAILURE);
        }

        ret = listen(passive_socket, BACKLOG);
        if (ret == -1) {
            perror("listen");
            exit(EXIT_FAILURE);
        }

        FD_SET(passive_socket, &read_set);
        maxFd = passive_socket;
        socket_initialized = true;
        return 0;
    }


    int writeCommandPacket(int cfd, aos_socket_command_packet & cmd_pckt) {
        if (!socket_initialized) {
            printError("Can't write command packet without an open socket");
        }
        if (write(cfd, &cmd_pckt, sizeof(aos_socket_command_packet)) < (int)sizeof(aos_socket_command_packet)) {
            printError("Daemon socket write error");
            close(cfd);
            FD_CLR(cfd, &read_set);
            open_fds.erase(cfd);
        }
        return 0;
    }

    int writeResponsePacket(int cfd, aos_socket_response_packet & resp_pckt) {
        if (!socket_initialized) {
            printError("Can't write response packet without an open socket");
        }
        if (write(cfd, &resp_pckt, sizeof(aos_socket_response_packet)) < (int)sizeof(aos_socket_response_packet)) {
            printError("Daemon socket write response error");
            close(cfd);
            FD_CLR(cfd, &read_set);
            open_fds.erase(cfd);
        }
        return 0;
    }

    int readCommandPacket(int cfd, aos_socket_command_packet & cmd_pckt) {
        if (read(cfd, &cmd_pckt, sizeof(aos_socket_command_packet)) < (int)sizeof(aos_socket_command_packet)) {
            //perror("Unable to read from client");
            close(cfd);
            FD_CLR(cfd, &read_set);
            open_fds.erase(cfd);
            return 1;
        }
        return 0;
    }

    void startTransaction(int & cfd) {
restartTransaction:
        fd_set temp_set = read_set; 

        // Select fd with data
        if (select(maxFd+1, &temp_set, nullptr, nullptr, nullptr) < 1) {
            printf("select error\n");
            goto restartTransaction;
        }

        // Add new connections to read set
        if (FD_ISSET(passive_socket, &temp_set)) {
            cfd = accept(passive_socket, NULL, NULL);
            if (cfd == -1) {
                perror("accept error");
            }
            FD_SET(cfd, &read_set);
            if (cfd > maxFd) maxFd = cfd;
            open_fds.insert(cfd);
            //printf("new connection: %d\n", cfd);
            goto restartTransaction;
        }

        // Identify source of command
        cfd = -1;
        for (int fd : open_fds) {
            if (FD_ISSET(fd, &temp_set)) cfd = fd;
        }
        //printf("old connection: %d\n", cfd);
        if (cfd == -1) {
           printf("bad select\n");
           goto restartTransaction;
        }
    }

    void closeTransaction(int cfd) {        
        if (false && close(cfd) == -1) {
            perror("close error on daemon");
        }
    }

    void listen_loop() {

        aos_socket_command_packet cmd_pckt;
        int cfd;

        while (1) {

            startTransaction(cfd);

            if (readCommandPacket(cfd, cmd_pckt)) continue;

            //std::cout << "Daemon Received 64 bit value: " <<  cmd_pckt.data64 << " for app " << cmd_pckt.app_id << " for addr " << cmd_pckt.addr64 << std::endl << std::flush;

            handleTransaction(cfd, cmd_pckt);

            closeTransaction(cfd);

        }

    }

    int handleTransaction(int cfd, aos_socket_command_packet & cmd_pckt) {
        switch(cmd_pckt.command_type) {
            case aos_socket_command::CNTRLREG_WRITE_REQUEST : {
                return handleCntrlRegWriteRequest(cmd_pckt);
            }
            break;
            case aos_socket_command::CNTRLREG_READ_REQUEST : {
                return handleCntrlReqReadRequest(cmd_pckt);
            }
            break;
            case aos_socket_command::CNTRLREG_READ_RESPONSE : {
                return handleCntrlRegReadResponse(cfd, cmd_pckt);
            }
            break;
            default: {
                perror("Unimplemented command type in daemon");
            }
            break;
        }
        return 0;
    }

    int handleCntrlRegWriteRequest(aos_socket_command_packet & cmd_pckt) {
        uint64_t slot_id_   = cmd_pckt.slot_id;
        uint64_t app_id_ = cmd_pckt.app_id;
        int success;
        if (!isDummy) {
            success = write_pci_bar(slot_id_, app_id_, cmd_pckt.addr64, cmd_pckt.data64);
        } else {
            if (dummy_cntrlreg_map.find(app_id_) == dummy_cntrlreg_map.end()) {
                dummy_cntrlreg_map[app_id_] = std::map<uint64_t, uint64_t>();
            }
            (dummy_cntrlreg_map[app_id_])[cmd_pckt.addr64] = cmd_pckt.data64;
            success = 0;
        }
        return success;
    }

    int handleCntrlReqReadRequest(aos_socket_command_packet & cmd_pckt) {
        uint64_t slot_id_   = cmd_pckt.slot_id;
        uint64_t app_id_    = cmd_pckt.app_id;
        uint64_t read_addr_ = cmd_pckt.addr64;

        int success;

        cntrlRegEnqReadReq(app_id_, read_addr_);
        if (!isDummy) {
            uint64_t read_value_;
            cntrlRegDeqReadReq(app_id_);
            success = read_pci_bar(slot_id_, app_id_, read_addr_, read_value_);
            if (success != 0) {
                perror("Read over pci bar failed on the daemon");
            }
            cntrlRegEnqReadResp(app_id_, read_value_);
        } else {
            if (dummy_cntrlreg_map.find(app_id_) == dummy_cntrlreg_map.end()) {
                dummy_cntrlreg_map[app_id_] = std::map<uint64_t, uint64_t>();
            }
            auto & app_cntrl_reg_map = dummy_cntrlreg_map[app_id_];
            if (app_cntrl_reg_map.find(read_addr_) == app_cntrl_reg_map.end()) {
                app_cntrl_reg_map[read_addr_] = 0x0;
            }
            cntrlRegDeqReadReq(app_id_);
            cntrlRegEnqReadResp(app_id_, app_cntrl_reg_map[read_addr_]);
            success = 0;
        }
        return success;
    }

    int handleCntrlRegReadResponse(int cfd, aos_socket_command_packet & cmd_pckt) {
        uint64_t app_id_ = cmd_pckt.app_id;
        uint64_t data64_;

        if (read_response_queue[app_id_].size() == 0) {
            perror("No available data to return for the read response");
        }

        if (!isDummy) {
            data64_ = cntrlRegDeqReadResp(app_id_);
        } else {
            data64_ = cntrlRegDeqReadResp(app_id_);
        }

        aos_socket_response_packet resp_pckt;
        resp_pckt.errorcode = aos_errcode::SUCCESS;
        resp_pckt.data64    = data64_;

        writeResponsePacket(cfd, resp_pckt);
        return 0;
    }

    int fpga_init() {
        /* initialize the fpga_pci library so we could have access to FPGA PCIe from this applications */
        int rc = fpga_mgmt_init();
        fail_on(rc, out, "Unable to initialize the fpga_mgmt library");
        printf("fpga_mgmt library intialized correctly\n");
        return rc;
        out:
            return 1;
    }

    int check_slot(int slot_id) {
        /* check the afi */
        int rc = check_afi_ready(slot_id);
        fail_on(rc, out, "AFI not ready\n");
        printf("AFI is ready\n");
        return rc;
        out:
            return 1;
    }

    int attach_pci_bar(int slot_id) {
        // Can't already be attached
        if (bar_attached[slot_id]) {
            printf("bar already attached");
        }
        int rc = fpga_pci_attach(slot_id, FPGA_APP_PF, APP_PF_BAR0, 0, &pci_bar_handle[slot_id]);
        fail_on(rc, out, "Unable to attach to the AFI on slot id %d\n", slot_id);
        printf("Attached to bar\n");
        bar_attached[slot_id] = true;
        return rc;
        out:
            return 1;
    }

    int detach_pci_bar(int slot_id) {
        int rc = fpga_pci_detach(pci_bar_handle[slot_id]);
        fail_on(rc, out, "Unable detach pci_bar from the FPGA");
        return rc;
        out:
            return 1;
    }

    int write_pci_bar(uint64_t slot_id, uint64_t app_id, uint64_t addr, uint64_t value) {
        int rc;
        
        // Check if BAR is initialized
        if (!bar_attached[slot_id]) {
            rc = check_slot(slot_id);
            fail_on(rc, out, "Writing to slot that's not ready");
            attach_pci_bar(slot_id);
            rc = !bar_attached[slot_id];
            fail_on(rc, out, "Writing to slot that's not attached");
        }
        
        // Check the address is 64-bit aligned
        if ((addr % 8) != 0) {
            printf("Addr is not correctly aligned");
        }

        rc = fpga_pci_poke64(pci_bar_handle[slot_id], applyAppMaskForbar(app_id, addr), value);
        fail_on(rc, out, "Unable to write to bar");

        return rc;
        out:
            return 1;
    }

    int read_pci_bar(uint64_t slot_id, uint64_t app_id, uint64_t addr, uint64_t & value) {
        int rc;
        
        // Check if BAR is initialized
        if (!bar_attached[slot_id]) {
            rc = check_slot(slot_id);
            fail_on(rc, out, "Writing to slot that's not ready");
            attach_pci_bar(slot_id);
            rc = !bar_attached[slot_id];
            fail_on(rc, out, "Reading from slot that's not attached");
        }
        
        // Check the address is 64-bit aligned
        if ((addr % 8) != 0) {
            printf("Addr is not correctly aligned");
        }
        
        rc = fpga_pci_peek64(pci_bar_handle[slot_id], applyAppMaskForbar(app_id, addr) , &value);
        fail_on(rc, out, "Unable to do read from bar");

        return rc;
        out:
            return 1;
    }

private:

    // Dummy behavior
    const bool isDummy;
    std::map<uint64_t, std::map<uint64_t, uint64_t>> dummy_cntrlreg_map;

    // CntrlReq read/response state
    std::map<uint64_t, std::queue<uint64_t>> read_request_queue;
    std::map<uint64_t, std::queue<uint64_t>> read_response_queue;

    void cntrlRegEnqReadReq(uint64_t app_id, uint64_t read_addr) {
        if (read_request_queue.find(app_id) == read_request_queue.end()) {
            read_request_queue[app_id] = std::queue<uint64_t>();
        }
        read_request_queue[app_id].push(read_addr);
    }

    uint64_t cntrlRegDeqReadReq(uint64_t app_id) {
        if (read_request_queue.find(app_id) == read_request_queue.end()) {
            perror("Invalid app id for cntrl reg read req dequeu");
        }
        uint64_t addr = read_request_queue[app_id].front();
        read_request_queue[app_id].pop();
        return addr;
    }

    void cntrlRegEnqReadResp(uint64_t app_id, uint64_t data64) {
        if (read_response_queue.find(app_id) == read_response_queue.end()) {
            read_response_queue[app_id] = std::queue<uint64_t>();
        }
        //std::cout << "Daemon Enqueu resp: " << data64 << " for app: " << app_id << std::endl << std::flush;
        read_response_queue[app_id].push(data64);
    }

    uint64_t cntrlRegDeqReadResp(uint64_t app_id) {
        if (read_response_queue.find(app_id) == read_response_queue.end()) {
            perror("Invalid app id for cntrl reg read resp deque");
        }
        if (read_response_queue[app_id].size() == 0) {
            perror("No response ready");
        }
        uint64_t data64_ = read_response_queue[app_id].front();
        //std::cout << "Daemon Deqeue resp: " << data64_ << " for app: " << app_id << std::endl << std::flush;

        read_response_queue[app_id].pop();
        return data64_;
    }

    // Socket control
    // Create socket
    sockaddr_un socket_name;
    int passive_socket;
    bool socket_initialized;
    std::unordered_set<int> open_fds;
    fd_set read_set;
    int maxFd;

    // BARs
    const static int num_bars = 8;
    bool bar_attached[num_bars];
    pci_bar_handle_t pci_bar_handle[num_bars];

    // This function will apply the upper bit masks to the address
    uint64_t applyAppMaskForbar(uint64_t app_id, uint64_t addr) {
        addr = (addr >> 3) << 11;
        app_id = app_id << 3;
        return addr | app_id;
    }

    int check_afi_ready(int slot_id) {
        struct fpga_mgmt_image_info info = {0}; 
        int rc = 0;

        /* get local image description, contains status, vendor id, and device id. */
        rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
        fail_on(rc, out, "Unable to get AFI information from slot %d. Are you running as root?",slot_id);

        /* check to see if the slot is ready */
        if (info.status != FPGA_STATUS_LOADED) {
            rc = 1;
            fail_on(rc, out, "AFI in Slot %d is not in READY state !", slot_id);
        }

        printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n",
              info.spec.map[FPGA_APP_PF].vendor_id,
              info.spec.map[FPGA_APP_PF].device_id);

        /* confirm that the AFI that we expect is in fact loaded */
        if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id || info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
            printf("AFI does not show expected PCI vendor id and device ID. If the AFI "
                "was just loaded, it might need a rescan. Rescanning now.\n");

            rc = fpga_pci_rescan_slot_app_pfs(slot_id);
            fail_on(rc, out, "Unable to update PF for slot %d",slot_id);
            /* get local image description, contains status, vendor id, and device id. */
            rc = fpga_mgmt_describe_local_image(slot_id, &info,0);
            fail_on(rc, out, "Unable to get AFI information from slot %d",slot_id);

            printf("AFI PCI  Vendor ID: 0x%x, Device ID 0x%x\n", info.spec.map[FPGA_APP_PF].vendor_id, info.spec.map[FPGA_APP_PF].device_id);

            /* confirm that the AFI that we expect is in fact loaded after rescan */
            if (info.spec.map[FPGA_APP_PF].vendor_id != pci_vendor_id || info.spec.map[FPGA_APP_PF].device_id != pci_device_id) {
                rc = 1;
                fail_on(rc, out, "The PCI vendor id and device of the loaded AFI are not "
                    "the expected values.");
            }
        }
        
            return rc;
        out:
            return 1;

     }

    // Helper functions
    uint32_t upper32(uint64_t value) {
        return (value >> 32) & 0xFFFFFFFF;
    }

    uint32_t lower32(uint64_t value) {
        return value & 0xFFFFFFFF;
    }

};

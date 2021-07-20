import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module DNNWrapper
(
	// User clock and reset
	input  clk,
	input  rst,
	
	// Virtual memory interface
	axi_bus_t.slave axi_m,
	
	// Soft register interface
	input  SoftRegReq   softreg_req,
	output SoftRegResp  softreg_resp
);
	parameter app_num = 0;
	
	
	//// Legacy AMI interface
	AMIRequest  mem_reqs        [1:0];
	logic       mem_req_grants  [1:0];
	AMIResponse mem_resps       [1:0];
	logic       mem_resp_grants [1:0];
	
	// Interface emulation
	// Note: assumes use of BlockBuffer
	// mem_reqs[0].isWrite = 0
	// mem_reqs[1].isWrite = 1
	// mem_reqs[*].addr[5:0] = 0
	// mem_reqs[*].size = 64
	
	assign axi_m.arid = 0;
	assign axi_m.araddr = mem_reqs[0].addr;
	assign axi_m.arlen = 0;
	assign axi_m.arsize = 3'b110;
	assign axi_m.arvalid = mem_reqs[0].valid;
	assign mem_req_grants[0] = axi_m.arready;
	
	// Unused: axi_m.rid, axi_m.rresp, axi_m.rlast
	assign mem_resps[0].valid = axi_m.rvalid;
	assign mem_resps[0].data = axi_m.rdata;
	assign mem_resps[0].size = 64;
	assign axi_m.rready = mem_resp_grants[0];
	
	assign axi_m.awid = 0;
	assign axi_m.awaddr = mem_reqs[1].addr;
	assign axi_m.awlen = 0;
	assign axi_m.awsize = 3'b110;
	assign axi_m.awvalid = axi_m.wready && mem_reqs[1].valid;
	
	assign mem_req_grants[1] = axi_m.awready && axi_m.wready;
	
	assign axi_m.wid = 0;
	assign axi_m.wdata = mem_reqs[1].data;
	assign axi_m.wstrb = 64'hFFFFFFFFFFFFFFFF;
	assign axi_m.wlast = 1;
	assign axi_m.wvalid = axi_m.awready && mem_reqs[1].valid;
	
	// Unused: axi_m.bid, axi_m.bresp, axi_m.bvalid
	assign axi_m.bready = 1;
	
	
	//// Legacy PCIe interface
	PCIEPacket pcie_packet_in;
	logic      pcie_full_out;
	PCIEPacket pcie_packet_out;
	logic      pcie_grant_in;
	
	// Currently unsupported and unused, tie off
	assign pcie_packet_in = '{valid: 0, data: 0, slot: 0, pad: 0, last: 0};
	assign pcie_grant_in = 0;
	
	
	//// Legacy app instantiation
	DNNDrive_SoftReg dnn (
		.clk(clk),
		.rst(rst),
		
		.srcApp(app_num),
		
		.mem_reqs(mem_reqs),
		.mem_req_grants(mem_req_grants),
		.mem_resps(mem_resps),
		.mem_resp_grants(mem_resp_grants),
		
		.pcie_packet_in(pcie_packet_in),
		.pcie_full_out(pcie_full_out),
		.pcie_packet_out(pcie_packet_out),
		.pcie_grant_in(pcie_grant_in),
		
		.softreg_req(softreg_req),
		.softreg_resp(softreg_resp)
	);

endmodule

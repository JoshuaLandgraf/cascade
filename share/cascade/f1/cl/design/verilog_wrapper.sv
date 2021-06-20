import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module VerilogWrapper
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
	
	program_logic
	#(
		.app_num(app_num)
	) pl (
		.clk(clk),
		.rst(rst),
		
		.arid_m(axi_m.arid),
		.araddr_m(axi_m.araddr),
		.arlen_m(axi_m.arlen),
		.arsize_m(axi_m.arsize),
		.arvalid_m(axi_m.arvalid),
		.arready_m(axi_m.arready),
		
		.rid_m(axi_m.rid),
		.rdata_m(axi_m.rdata),
		.rresp_m(axi_m.rresp),
		.rlast_m(axi_m.rlast),
		.rvalid_m(axi_m.rvalid),
		.rready_m(axi_m.rready),
		
		.awid_m(axi_m.awid),
		.awaddr_m(axi_m.awaddr),
		.awlen_m(axi_m.awlen),
		.awsize_m(axi_m.awsize),
		.awvalid_m(axi_m.awvalid),
		.awready_m(axi_m.awready),
		
		.wid_m(axi_m.wid),
		.wdata_m(axi_m.wdata),
		.wstrb_m(axi_m.wstrb),
		.wlast_m(axi_m.wlast),
		.wvalid_m(axi_m.wvalid),
		.wready_m(axi_m.wready),
		
		.bid_m(axi_m.bid),
		.bresp_m(axi_m.bresp),
		.bvalid_m(axi_m.bvalid),
		.bready_m(axi_m.bready),
		
		.softreg_req_valid(softreg_req.valid),
		.softreg_req_isWrite(softreg_req.isWrite),
		.softreg_req_addr(softreg_req.addr),
		.softreg_req_data(softreg_req.data),
		
		.softreg_resp_valid(softreg_resp.valid),
		.softreg_resp_data(softreg_resp.data)
	);

endmodule

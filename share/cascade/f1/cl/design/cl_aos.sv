/*

    Top level module for running on an F1 instance

    Written by Ahmed Khawaja

*/

import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

module cl_aos (
   `include "cl_ports.vh" // Fixed port definition
);

`include "cl_common_defines.vh"      // CL Defines for all examples
`include "cl_id_defines.vh"          // Defines for ID0 and ID1 (PCI ID's)
`include "cl_aos_defines.vh" // CL Defines for cl_hello_world

// CL Version

`ifndef CL_VERSION
   `define CL_VERSION 32'hee_ee_ee_00
`endif

//--------------------------------------------
// Start with Tie-Off of Unused Interfaces
//--------------------------------------------
// the developer should use the next set of `include
// to properly tie-off any unused interface
// The list is put in the top of the module
// to avoid cases where developer may forget to
// remove it from the end of the file

// User defined interrupts, NOT USED
`include "unused_apppf_irq_template.inc"
// Function level reset, NOT USED
`include "unused_flr_template.inc"
// Main PCI-e in/out interfaces, currently not used
`include "unused_pcim_template.inc"
//`include "unused_dma_pcis_template.inc"
// Unused AXIL interfaces
`include "unused_cl_sda_template.inc"
//`include "unused_sh_ocl_template.inc"
//`include "unused_sh_bar1_template.inc"

// Gen vars
genvar i;
genvar app_num;

// Global signals
logic global_clk = clk_main_a0;
logic global_rst_n;
logic global_rst;

//------------------------------------
// Reset Synchronization
//------------------------------------
// Reset synchronizer
(* dont_touch = "true" *) logic pipe_rst_n;

lib_pipe #(.WIDTH(1), .STAGES(3)) PIPE_RST_N (.clk(global_clk), .rst_n(1'b1), .in_bus(rst_main_n), .out_bus(pipe_rst_n));

assign global_rst_n = pipe_rst_n;
assign global_rst   = !pipe_rst_n;


//------------------------------------
// System SoftReg
//------------------------------------

// Mapped onto BAR1
/*
|----- AppPF  
|   |------- BAR1
|   |         * 32-bit BAR, non-prefetchable
|   |         * 2MiB (0 to 0x1F-FFFF)
|   |         * Maps to BAR1 AXI-L of the CL
|   |         * Typically used for CL application registers 
*/

// AXIL2SR to AmorphOS System
SoftRegReq  sys_softreg_req;
SoftRegReq  sys_softreg_req_buf;
logic       sys_softreg_req_grant;

SoftRegResp sys_softreg_resp;
SoftRegResp sys_softreg_resp_buf;
logic       sys_softreg_resp_grant;

AXIL2SR
axil2sr_inst_sys
(
	// General Signals
	.clk(global_clk),
	.rst(global_rst), // expects active high
	
	// Write Address
	.sh_awvalid(sh_bar1_awvalid),
	.sh_awaddr(sh_bar1_awaddr),
	.sh_awready(bar1_sh_awready),
	
	//Write data
	.sh_wvalid(sh_bar1_wvalid),
	.sh_wdata(sh_bar1_wdata),
	.sh_wstrb(sh_bar1_wstrb),
	.sh_wready(bar1_sh_wready),
	
	//Write response
	.sh_bvalid(bar1_sh_bvalid),
	.sh_bresp(bar1_sh_bresp),
	.sh_bready(sh_bar1_bready),
	
	//Read address
	.sh_arvalid(sh_bar1_arvalid),
	.sh_araddr(sh_bar1_araddr),
	.sh_arready(bar1_sh_arready),
	
	//Read data/response
	.sh_rvalid(bar1_sh_rvalid),
	.sh_rdata(bar1_sh_rdata),
	.sh_rresp(bar1_sh_rresp),
	.sh_rready(sh_bar1_rready),
	
	// Interface to SoftReg
	// Requests
	.softreg_req(sys_softreg_req_buf),
	.softreg_req_grant(sys_softreg_req_grant),
	// Responses
	.softreg_resp(sys_softreg_resp_buf),
	.softreg_resp_grant(sys_softreg_resp_grant)
);
assign sys_softreg_req_grant = 1;

lib_pipe #(.WIDTH($bits(SoftRegReq)), .STAGES(2)) PIPE_sys_softreg_req (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus(sys_softreg_req_buf),
	.out_bus(sys_softreg_req)
);

lib_pipe #(.WIDTH($bits(SoftRegResp)), .STAGES(2)) PIPE_sys_softreg_resp (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus(sys_softreg_resp),
	.out_bus(sys_softreg_resp_buf)
);


//------------------------------------
// DRAM DMA
//------------------------------------

// Internal signals
axi_bus_t lcl_cl_sh_ddra();
axi_bus_t lcl_cl_sh_ddrb();
axi_bus_t lcl_cl_sh_ddrd();
axi_bus_t axi_bus_tied();

axi_bus_t sh_cl_dma_pcis_bus();

axi_bus_t cl_axi_mstr_bus [3:0] ();

axi_bus_t cl_sh_pcim_bus();
axi_bus_t cl_sh_ddr_bus();

logic [3:0] all_ddr_is_ready;
logic [2:0] lcl_sh_cl_ddr_is_ready;

// Unused 'full' signals
assign cl_sh_dma_rd_full  = 1'b0;
assign cl_sh_dma_wr_full  = 1'b0;

// Unused *burst signals
assign cl_sh_ddr_arburst[1:0] = 2'b01;
assign cl_sh_ddr_awburst[1:0] = 2'b01;

// DDR Ready
logic sh_cl_ddr_is_ready_q;
always_ff @(posedge global_clk) // or negedge global_rst_n)
	if (!global_rst_n)
	begin
	sh_cl_ddr_is_ready_q <= 1'b0;
	end
	else
	begin
	sh_cl_ddr_is_ready_q <= sh_cl_ddr_is_ready;
	end  
	
assign all_ddr_is_ready = {lcl_sh_cl_ddr_is_ready[2], sh_cl_ddr_is_ready_q, lcl_sh_cl_ddr_is_ready[1:0]};

// Interface bridge
assign sh_cl_dma_pcis_bus.awvalid = sh_cl_dma_pcis_awvalid;
assign sh_cl_dma_pcis_bus.awaddr = sh_cl_dma_pcis_awaddr;
assign sh_cl_dma_pcis_bus.awid[5:0] = sh_cl_dma_pcis_awid;
assign sh_cl_dma_pcis_bus.awlen = sh_cl_dma_pcis_awlen;
assign sh_cl_dma_pcis_bus.awsize = sh_cl_dma_pcis_awsize;
assign cl_sh_dma_pcis_awready = sh_cl_dma_pcis_bus.awready;
assign sh_cl_dma_pcis_bus.wvalid = sh_cl_dma_pcis_wvalid;
assign sh_cl_dma_pcis_bus.wdata = sh_cl_dma_pcis_wdata;
assign sh_cl_dma_pcis_bus.wstrb = sh_cl_dma_pcis_wstrb;
assign sh_cl_dma_pcis_bus.wlast = sh_cl_dma_pcis_wlast;
assign cl_sh_dma_pcis_wready = sh_cl_dma_pcis_bus.wready;
assign cl_sh_dma_pcis_bvalid = sh_cl_dma_pcis_bus.bvalid;
assign cl_sh_dma_pcis_bresp = sh_cl_dma_pcis_bus.bresp;
assign sh_cl_dma_pcis_bus.bready = sh_cl_dma_pcis_bready;
assign cl_sh_dma_pcis_bid = sh_cl_dma_pcis_bus.bid[5:0];
assign sh_cl_dma_pcis_bus.arvalid = sh_cl_dma_pcis_arvalid;
assign sh_cl_dma_pcis_bus.araddr = sh_cl_dma_pcis_araddr;
assign sh_cl_dma_pcis_bus.arid[5:0] = sh_cl_dma_pcis_arid;
assign sh_cl_dma_pcis_bus.arlen = sh_cl_dma_pcis_arlen;
assign sh_cl_dma_pcis_bus.arsize = sh_cl_dma_pcis_arsize;
assign cl_sh_dma_pcis_arready = sh_cl_dma_pcis_bus.arready;
assign cl_sh_dma_pcis_rvalid = sh_cl_dma_pcis_bus.rvalid;
assign cl_sh_dma_pcis_rid = sh_cl_dma_pcis_bus.rid[5:0];
assign cl_sh_dma_pcis_rlast = sh_cl_dma_pcis_bus.rlast;
assign cl_sh_dma_pcis_rresp = sh_cl_dma_pcis_bus.rresp;
assign cl_sh_dma_pcis_rdata = sh_cl_dma_pcis_bus.rdata;
assign sh_cl_dma_pcis_bus.rready = sh_cl_dma_pcis_rready;

assign cl_sh_ddr_awid = cl_sh_ddr_bus.awid;
assign cl_sh_ddr_awaddr = cl_sh_ddr_bus.awaddr;
assign cl_sh_ddr_awlen = cl_sh_ddr_bus.awlen;
assign cl_sh_ddr_awsize = cl_sh_ddr_bus.awsize;
assign cl_sh_ddr_awvalid = cl_sh_ddr_bus.awvalid;
assign cl_sh_ddr_bus.awready = sh_cl_ddr_awready;
assign cl_sh_ddr_wid = 16'b0;
assign cl_sh_ddr_wdata = cl_sh_ddr_bus.wdata;
assign cl_sh_ddr_wstrb = cl_sh_ddr_bus.wstrb;
assign cl_sh_ddr_wlast = cl_sh_ddr_bus.wlast;
assign cl_sh_ddr_wvalid = cl_sh_ddr_bus.wvalid;
assign cl_sh_ddr_bus.wready = sh_cl_ddr_wready;
assign cl_sh_ddr_bus.bid = sh_cl_ddr_bid;
assign cl_sh_ddr_bus.bresp = sh_cl_ddr_bresp;
assign cl_sh_ddr_bus.bvalid = sh_cl_ddr_bvalid;
assign cl_sh_ddr_bready = cl_sh_ddr_bus.bready;
assign cl_sh_ddr_arid = cl_sh_ddr_bus.arid;
assign cl_sh_ddr_araddr = cl_sh_ddr_bus.araddr;
assign cl_sh_ddr_arlen = cl_sh_ddr_bus.arlen;
assign cl_sh_ddr_arsize = cl_sh_ddr_bus.arsize;
assign cl_sh_ddr_arvalid = cl_sh_ddr_bus.arvalid;
assign cl_sh_ddr_bus.arready = sh_cl_ddr_arready;
assign cl_sh_ddr_bus.rid = sh_cl_ddr_rid;
assign cl_sh_ddr_bus.rresp = sh_cl_ddr_rresp;
assign cl_sh_ddr_bus.rvalid = sh_cl_ddr_rvalid;
assign cl_sh_ddr_bus.rdata = sh_cl_ddr_rdata;
assign cl_sh_ddr_bus.rlast = sh_cl_ddr_rlast;
assign cl_sh_ddr_rready = cl_sh_ddr_bus.rready;

// Interconnect
cl_dma_pcis_slv CL_DMA_PCIS_SLV (
	.aclk(global_clk),
	.aresetn(global_rst_n),
	
	.sys_softreg_req(sys_softreg_req),
	.sys_softreg_resp(sys_softreg_resp),
	
	.sh_cl_dma_pcis_bus(sh_cl_dma_pcis_bus),
	.cl_axi_mstr_bus_1(cl_axi_mstr_bus[0]),
	.cl_axi_mstr_bus_2(cl_axi_mstr_bus[1]),
	.cl_axi_mstr_bus_3(cl_axi_mstr_bus[2]),
	.cl_axi_mstr_bus_4(cl_axi_mstr_bus[3]),
	
	.lcl_cl_sh_ddra(lcl_cl_sh_ddra),
	.lcl_cl_sh_ddrb(lcl_cl_sh_ddrb),
	.lcl_cl_sh_ddrd(lcl_cl_sh_ddrd),
	
	.cl_sh_ddr_bus(cl_sh_ddr_bus)
);

// DDR Stats
localparam NUM_CFG_STGS_CL_DDR_ATG = 4;

logic[7:0] sh_ddr_stat_addr_q[2:0];
logic[2:0] sh_ddr_stat_wr_q;
logic[2:0] sh_ddr_stat_rd_q; 
logic[31:0] sh_ddr_stat_wdata_q[2:0];
logic[2:0] ddr_sh_stat_ack_q;
logic[31:0] ddr_sh_stat_rdata_q[2:0];
logic[7:0] ddr_sh_stat_int_q[2:0];

lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT0 (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus({sh_ddr_stat_wr0, sh_ddr_stat_rd0, sh_ddr_stat_addr0, sh_ddr_stat_wdata0}),
	.out_bus({sh_ddr_stat_wr_q[0], sh_ddr_stat_rd_q[0], sh_ddr_stat_addr_q[0], sh_ddr_stat_wdata_q[0]})
);

lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK0 (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus({ddr_sh_stat_ack_q[0], ddr_sh_stat_int_q[0], ddr_sh_stat_rdata_q[0]}),
	.out_bus({ddr_sh_stat_ack0, ddr_sh_stat_int0, ddr_sh_stat_rdata0})
);

lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT1 (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus({sh_ddr_stat_wr1, sh_ddr_stat_rd1, sh_ddr_stat_addr1, sh_ddr_stat_wdata1}),
	.out_bus({sh_ddr_stat_wr_q[1], sh_ddr_stat_rd_q[1], sh_ddr_stat_addr_q[1], sh_ddr_stat_wdata_q[1]})
);

lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK1 (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus({ddr_sh_stat_ack_q[1], ddr_sh_stat_int_q[1], ddr_sh_stat_rdata_q[1]}),
	.out_bus({ddr_sh_stat_ack1, ddr_sh_stat_int1, ddr_sh_stat_rdata1})
);

lib_pipe #(.WIDTH(1+1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT2 (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus({sh_ddr_stat_wr2, sh_ddr_stat_rd2, sh_ddr_stat_addr2, sh_ddr_stat_wdata2}),
	.out_bus({sh_ddr_stat_wr_q[2], sh_ddr_stat_rd_q[2], sh_ddr_stat_addr_q[2], sh_ddr_stat_wdata_q[2]})
);

lib_pipe #(.WIDTH(1+8+32), .STAGES(NUM_CFG_STGS_CL_DDR_ATG)) PIPE_DDR_STAT_ACK2 (
	.clk(global_clk),
	.rst_n(global_rst_n),
	.in_bus({ddr_sh_stat_ack_q[2], ddr_sh_stat_int_q[2], ddr_sh_stat_rdata_q[2]}),
	.out_bus({ddr_sh_stat_ack2, ddr_sh_stat_int2, ddr_sh_stat_rdata2})
);

// DDR Controllers
logic[15:0] cl_sh_ddr_awid_2d[2:0];
logic[63:0] cl_sh_ddr_awaddr_2d[2:0];
logic[7:0] cl_sh_ddr_awlen_2d[2:0];
logic[2:0] cl_sh_ddr_awsize_2d[2:0];
logic[1:0] cl_sh_ddr_awburst_2d[2:0];
logic cl_sh_ddr_awvalid_2d [2:0];
logic[2:0] sh_cl_ddr_awready_2d;

logic[15:0] cl_sh_ddr_wid_2d[2:0];
logic[511:0] cl_sh_ddr_wdata_2d[2:0];
logic[63:0] cl_sh_ddr_wstrb_2d[2:0];
logic[2:0] cl_sh_ddr_wlast_2d;
logic[2:0] cl_sh_ddr_wvalid_2d;
logic[2:0] sh_cl_ddr_wready_2d;

logic[15:0] sh_cl_ddr_bid_2d[2:0];
logic[1:0] sh_cl_ddr_bresp_2d[2:0];
logic[2:0] sh_cl_ddr_bvalid_2d;
logic[2:0] cl_sh_ddr_bready_2d;

logic[15:0] cl_sh_ddr_arid_2d[2:0];
logic[63:0] cl_sh_ddr_araddr_2d[2:0];
logic[7:0] cl_sh_ddr_arlen_2d[2:0];
logic[2:0] cl_sh_ddr_arsize_2d[2:0];
logic[1:0] cl_sh_ddr_arburst_2d[2:0];
logic[2:0] cl_sh_ddr_arvalid_2d;
logic[2:0] sh_cl_ddr_arready_2d;

logic[15:0] sh_cl_ddr_rid_2d[2:0];
logic[511:0] sh_cl_ddr_rdata_2d[2:0];
logic[1:0] sh_cl_ddr_rresp_2d[2:0];
logic[2:0] sh_cl_ddr_rlast_2d;
logic[2:0] sh_cl_ddr_rvalid_2d;
logic[2:0] cl_sh_ddr_rready_2d;

assign cl_sh_ddr_awid_2d = '{lcl_cl_sh_ddrd.awid, lcl_cl_sh_ddrb.awid, lcl_cl_sh_ddra.awid};
assign cl_sh_ddr_awaddr_2d = '{lcl_cl_sh_ddrd.awaddr, lcl_cl_sh_ddrb.awaddr, lcl_cl_sh_ddra.awaddr};
assign cl_sh_ddr_awlen_2d = '{lcl_cl_sh_ddrd.awlen, lcl_cl_sh_ddrb.awlen, lcl_cl_sh_ddra.awlen};
assign cl_sh_ddr_awsize_2d = '{lcl_cl_sh_ddrd.awsize, lcl_cl_sh_ddrb.awsize, lcl_cl_sh_ddra.awsize};
assign cl_sh_ddr_awvalid_2d = '{lcl_cl_sh_ddrd.awvalid, lcl_cl_sh_ddrb.awvalid, lcl_cl_sh_ddra.awvalid};
assign cl_sh_ddr_awburst_2d = {2'b01, 2'b01, 2'b01};
assign {lcl_cl_sh_ddrd.awready, lcl_cl_sh_ddrb.awready, lcl_cl_sh_ddra.awready} = sh_cl_ddr_awready_2d;

assign cl_sh_ddr_wid_2d = '{lcl_cl_sh_ddrd.wid, lcl_cl_sh_ddrb.wid, lcl_cl_sh_ddra.wid};
assign cl_sh_ddr_wdata_2d = '{lcl_cl_sh_ddrd.wdata, lcl_cl_sh_ddrb.wdata, lcl_cl_sh_ddra.wdata};
assign cl_sh_ddr_wstrb_2d = '{lcl_cl_sh_ddrd.wstrb, lcl_cl_sh_ddrb.wstrb, lcl_cl_sh_ddra.wstrb};
assign cl_sh_ddr_wlast_2d = {lcl_cl_sh_ddrd.wlast, lcl_cl_sh_ddrb.wlast, lcl_cl_sh_ddra.wlast};
assign cl_sh_ddr_wvalid_2d = {lcl_cl_sh_ddrd.wvalid, lcl_cl_sh_ddrb.wvalid, lcl_cl_sh_ddra.wvalid};
assign {lcl_cl_sh_ddrd.wready, lcl_cl_sh_ddrb.wready, lcl_cl_sh_ddra.wready} = sh_cl_ddr_wready_2d;

assign {lcl_cl_sh_ddrd.bid, lcl_cl_sh_ddrb.bid, lcl_cl_sh_ddra.bid} = {sh_cl_ddr_bid_2d[2], sh_cl_ddr_bid_2d[1], sh_cl_ddr_bid_2d[0]};
assign {lcl_cl_sh_ddrd.bresp, lcl_cl_sh_ddrb.bresp, lcl_cl_sh_ddra.bresp} = {sh_cl_ddr_bresp_2d[2], sh_cl_ddr_bresp_2d[1], sh_cl_ddr_bresp_2d[0]};
assign {lcl_cl_sh_ddrd.bvalid, lcl_cl_sh_ddrb.bvalid, lcl_cl_sh_ddra.bvalid} = sh_cl_ddr_bvalid_2d;
assign cl_sh_ddr_bready_2d = {lcl_cl_sh_ddrd.bready, lcl_cl_sh_ddrb.bready, lcl_cl_sh_ddra.bready};

assign cl_sh_ddr_arid_2d = '{lcl_cl_sh_ddrd.arid, lcl_cl_sh_ddrb.arid, lcl_cl_sh_ddra.arid};
assign cl_sh_ddr_araddr_2d = '{lcl_cl_sh_ddrd.araddr, lcl_cl_sh_ddrb.araddr, lcl_cl_sh_ddra.araddr};
assign cl_sh_ddr_arlen_2d = '{lcl_cl_sh_ddrd.arlen, lcl_cl_sh_ddrb.arlen, lcl_cl_sh_ddra.arlen};
assign cl_sh_ddr_arsize_2d = '{lcl_cl_sh_ddrd.arsize, lcl_cl_sh_ddrb.arsize, lcl_cl_sh_ddra.arsize};
assign cl_sh_ddr_arvalid_2d = {lcl_cl_sh_ddrd.arvalid, lcl_cl_sh_ddrb.arvalid, lcl_cl_sh_ddra.arvalid};
assign cl_sh_ddr_arburst_2d = {2'b01, 2'b01, 2'b01};
assign {lcl_cl_sh_ddrd.arready, lcl_cl_sh_ddrb.arready, lcl_cl_sh_ddra.arready} = sh_cl_ddr_arready_2d;

assign {lcl_cl_sh_ddrd.rid, lcl_cl_sh_ddrb.rid, lcl_cl_sh_ddra.rid} = {sh_cl_ddr_rid_2d[2], sh_cl_ddr_rid_2d[1], sh_cl_ddr_rid_2d[0]};
assign {lcl_cl_sh_ddrd.rresp, lcl_cl_sh_ddrb.rresp, lcl_cl_sh_ddra.rresp} = {sh_cl_ddr_rresp_2d[2], sh_cl_ddr_rresp_2d[1], sh_cl_ddr_rresp_2d[0]};
assign {lcl_cl_sh_ddrd.rdata, lcl_cl_sh_ddrb.rdata, lcl_cl_sh_ddra.rdata} = {sh_cl_ddr_rdata_2d[2], sh_cl_ddr_rdata_2d[1], sh_cl_ddr_rdata_2d[0]};
assign {lcl_cl_sh_ddrd.rlast, lcl_cl_sh_ddrb.rlast, lcl_cl_sh_ddra.rlast} = sh_cl_ddr_rlast_2d;
assign {lcl_cl_sh_ddrd.rvalid, lcl_cl_sh_ddrb.rvalid, lcl_cl_sh_ddra.rvalid} = sh_cl_ddr_rvalid_2d;
assign cl_sh_ddr_rready_2d = {lcl_cl_sh_ddrd.rready, lcl_cl_sh_ddrb.rready, lcl_cl_sh_ddra.rready};

sh_ddr #(
	.DDR_A_PRESENT(1),
	.DDR_B_PRESENT(1),
	.DDR_D_PRESENT(1)
) SH_DDR (
	.clk(global_clk),
	.rst_n(global_rst_n),
	
	.stat_clk(global_clk),
	.stat_rst_n(global_rst_n),
	
	.CLK_300M_DIMM0_DP(CLK_300M_DIMM0_DP),
	.CLK_300M_DIMM0_DN(CLK_300M_DIMM0_DN),
	.M_A_ACT_N(M_A_ACT_N),
	.M_A_MA(M_A_MA),
	.M_A_BA(M_A_BA),
	.M_A_BG(M_A_BG),
	.M_A_CKE(M_A_CKE),
	.M_A_ODT(M_A_ODT),
	.M_A_CS_N(M_A_CS_N),
	.M_A_CLK_DN(M_A_CLK_DN),
	.M_A_CLK_DP(M_A_CLK_DP),
	.M_A_PAR(M_A_PAR),
	.M_A_DQ(M_A_DQ),
	.M_A_ECC(M_A_ECC),
	.M_A_DQS_DP(M_A_DQS_DP),
	.M_A_DQS_DN(M_A_DQS_DN),
	.cl_RST_DIMM_A_N(cl_RST_DIMM_A_N),
	
	.CLK_300M_DIMM1_DP(CLK_300M_DIMM1_DP),
	.CLK_300M_DIMM1_DN(CLK_300M_DIMM1_DN),
	.M_B_ACT_N(M_B_ACT_N),
	.M_B_MA(M_B_MA),
	.M_B_BA(M_B_BA),
	.M_B_BG(M_B_BG),
	.M_B_CKE(M_B_CKE),
	.M_B_ODT(M_B_ODT),
	.M_B_CS_N(M_B_CS_N),
	.M_B_CLK_DN(M_B_CLK_DN),
	.M_B_CLK_DP(M_B_CLK_DP),
	.M_B_PAR(M_B_PAR),
	.M_B_DQ(M_B_DQ),
	.M_B_ECC(M_B_ECC),
	.M_B_DQS_DP(M_B_DQS_DP),
	.M_B_DQS_DN(M_B_DQS_DN),
	.cl_RST_DIMM_B_N(cl_RST_DIMM_B_N),
	
	.CLK_300M_DIMM3_DP(CLK_300M_DIMM3_DP),
	.CLK_300M_DIMM3_DN(CLK_300M_DIMM3_DN),
	.M_D_ACT_N(M_D_ACT_N),
	.M_D_MA(M_D_MA),
	.M_D_BA(M_D_BA),
	.M_D_BG(M_D_BG),
	.M_D_CKE(M_D_CKE),
	.M_D_ODT(M_D_ODT),
	.M_D_CS_N(M_D_CS_N),
	.M_D_CLK_DN(M_D_CLK_DN),
	.M_D_CLK_DP(M_D_CLK_DP),
	.M_D_PAR(M_D_PAR),
	.M_D_DQ(M_D_DQ),
	.M_D_ECC(M_D_ECC),
	.M_D_DQS_DP(M_D_DQS_DP),
	.M_D_DQS_DN(M_D_DQS_DN),
	.cl_RST_DIMM_D_N(cl_RST_DIMM_D_N),
	
	//------------------------------------------------------
	// DDR-4 Interface from CL (AXI-4)
	//------------------------------------------------------
	.cl_sh_ddr_awid(cl_sh_ddr_awid_2d),
	.cl_sh_ddr_awaddr(cl_sh_ddr_awaddr_2d),
	.cl_sh_ddr_awlen(cl_sh_ddr_awlen_2d),
	.cl_sh_ddr_awsize(cl_sh_ddr_awsize_2d),
	.cl_sh_ddr_awvalid(cl_sh_ddr_awvalid_2d),
	.cl_sh_ddr_awburst(cl_sh_ddr_awburst_2d),
	.sh_cl_ddr_awready(sh_cl_ddr_awready_2d),
	
	.cl_sh_ddr_wid(cl_sh_ddr_wid_2d),
	.cl_sh_ddr_wdata(cl_sh_ddr_wdata_2d),
	.cl_sh_ddr_wstrb(cl_sh_ddr_wstrb_2d),
	.cl_sh_ddr_wlast(cl_sh_ddr_wlast_2d),
	.cl_sh_ddr_wvalid(cl_sh_ddr_wvalid_2d),
	.sh_cl_ddr_wready(sh_cl_ddr_wready_2d),
	
	.sh_cl_ddr_bid(sh_cl_ddr_bid_2d),
	.sh_cl_ddr_bresp(sh_cl_ddr_bresp_2d),
	.sh_cl_ddr_bvalid(sh_cl_ddr_bvalid_2d),
	.cl_sh_ddr_bready(cl_sh_ddr_bready_2d),
	
	.cl_sh_ddr_arid(cl_sh_ddr_arid_2d),
	.cl_sh_ddr_araddr(cl_sh_ddr_araddr_2d),
	.cl_sh_ddr_arlen(cl_sh_ddr_arlen_2d),
	.cl_sh_ddr_arsize(cl_sh_ddr_arsize_2d),
	.cl_sh_ddr_arvalid(cl_sh_ddr_arvalid_2d),
	.cl_sh_ddr_arburst(cl_sh_ddr_arburst_2d),
	.sh_cl_ddr_arready(sh_cl_ddr_arready_2d),
	
	.sh_cl_ddr_rid(sh_cl_ddr_rid_2d),
	.sh_cl_ddr_rdata(sh_cl_ddr_rdata_2d),
	.sh_cl_ddr_rresp(sh_cl_ddr_rresp_2d),
	.sh_cl_ddr_rlast(sh_cl_ddr_rlast_2d),
	.sh_cl_ddr_rvalid(sh_cl_ddr_rvalid_2d),
	.cl_sh_ddr_rready(cl_sh_ddr_rready_2d),
	
	.sh_cl_ddr_is_ready(lcl_sh_cl_ddr_is_ready),
	
	.sh_ddr_stat_addr0  (sh_ddr_stat_addr_q[0]),
	.sh_ddr_stat_wr0    (sh_ddr_stat_wr_q[0]),
	.sh_ddr_stat_rd0    (sh_ddr_stat_rd_q[0]),
	.sh_ddr_stat_wdata0 (sh_ddr_stat_wdata_q[0]),
	.ddr_sh_stat_ack0   (ddr_sh_stat_ack_q[0]),
	.ddr_sh_stat_rdata0 (ddr_sh_stat_rdata_q[0]),
	.ddr_sh_stat_int0   (ddr_sh_stat_int_q[0]),
	
	.sh_ddr_stat_addr1  (sh_ddr_stat_addr_q[1]),
	.sh_ddr_stat_wr1    (sh_ddr_stat_wr_q[1]),
	.sh_ddr_stat_rd1    (sh_ddr_stat_rd_q[1]),
	.sh_ddr_stat_wdata1 (sh_ddr_stat_wdata_q[1]),
	.ddr_sh_stat_ack1   (ddr_sh_stat_ack_q[1]),
	.ddr_sh_stat_rdata1 (ddr_sh_stat_rdata_q[1]),
	.ddr_sh_stat_int1   (ddr_sh_stat_int_q[1]),
	
	.sh_ddr_stat_addr2  (sh_ddr_stat_addr_q[2]),
	.sh_ddr_stat_wr2    (sh_ddr_stat_wr_q[2]),
	.sh_ddr_stat_rd2    (sh_ddr_stat_rd_q[2]),
	.sh_ddr_stat_wdata2 (sh_ddr_stat_wdata_q[2]),
	.ddr_sh_stat_ack2   (ddr_sh_stat_ack_q[2]),
	.ddr_sh_stat_rdata2 (ddr_sh_stat_rdata_q[2]),
	.ddr_sh_stat_int2   (ddr_sh_stat_int_q[2])
);

//------------------------------------
// App and port enables
//------------------------------------
logic app_enable [F1_NUM_APPS-1:0];

genvar port_num;
generate
	for (app_num = 0; app_num < F1_NUM_APPS; app_num = app_num + 1) begin : enables_set
		assign app_enable[app_num] = 1'b1;
	end
endgenerate
   
//------------------------------------
// Application SoftReg
//------------------------------------

// Mapped onto BAR0 
/* AppPF
  |   |------- BAR0
  |   |         * 32-bit BAR, non-prefetchable
  |   |         * 32MiB (0 to 0x1FF-FFFF)
  |   |         * Maps to BAR0 AXI-L of the CL 
*/

// AXIL2SR to AmorphOS
SoftRegReq  softreg_req_from_axil2sr;
logic       softreg_req_grant_to_axil2sr;

SoftRegResp softreg_resp_to_axil2sr;
logic       softreg_resp_grant_from_axil2sr;  

generate
	if (F1_AXIL_USE_EXTENDER == 1) begin : extender_axil2sr
		AXIL2SR_Extended
		axil2sr_inst_extended
		(
			// General Signals
			.clk(global_clk),
			.rst(global_rst), // expects active high

			// Write Address
			.sh_awvalid(sh_ocl_awvalid),
			.sh_awaddr(sh_ocl_awaddr),
			.sh_awready(ocl_sh_awready),

			//Write data
			.sh_wvalid(sh_ocl_wvalid),
			.sh_wdata(sh_ocl_wdata),
			.sh_wstrb(sh_ocl_wstrb),
			.sh_wready(ocl_sh_wready),

			//Write response
			.sh_bvalid(ocl_sh_bvalid),
			.sh_bresp(ocl_sh_bresp),
			.sh_bready(sh_ocl_bready),

			//Read address
			.sh_arvalid(sh_ocl_arvalid),
			.sh_araddr(sh_ocl_araddr),
			.sh_arready(ocl_sh_arready),

			//Read data/response
			.sh_rvalid(ocl_sh_rvalid),
			.sh_rdata(ocl_sh_rdata),
			.sh_rresp(ocl_sh_rresp),
			.sh_rready(sh_ocl_rready),

			// Interface to SoftReg
			// Requests
			.softreg_req(softreg_req_from_axil2sr),
			.softreg_req_grant(softreg_req_grant_to_axil2sr),
			// Responses
			.softreg_resp(softreg_resp_to_axil2sr),
			.softreg_resp_grant(softreg_resp_grant_from_axil2sr)
		);
	end else begin : normal_axil2sr
		AXIL2SR
		axil2sr_inst 
		(
			// General Signals
			.clk(global_clk),
			.rst(global_rst), // expects active high

			// Write Address
			.sh_awvalid(sh_ocl_awvalid),
			.sh_awaddr(sh_ocl_awaddr),
			.sh_awready(ocl_sh_awready),

			//Write data
			.sh_wvalid(sh_ocl_wvalid),
			.sh_wdata(sh_ocl_wdata),
			.sh_wstrb(sh_ocl_wstrb),
			.sh_wready(ocl_sh_wready),

			//Write response
			.sh_bvalid(ocl_sh_bvalid),
			.sh_bresp(ocl_sh_bresp),
			.sh_bready(sh_ocl_bready),

			//Read address
			.sh_arvalid(sh_ocl_arvalid),
			.sh_araddr(sh_ocl_araddr),
			.sh_arready(ocl_sh_arready),

			//Read data/response
			.sh_rvalid(ocl_sh_rvalid),
			.sh_rdata(ocl_sh_rdata),
			.sh_rresp(ocl_sh_rresp),
			.sh_rready(sh_ocl_rready),

			// Interface to SoftReg
			// Requests
			.softreg_req(softreg_req_from_axil2sr),
			.softreg_req_grant(softreg_req_grant_to_axil2sr),
			// Responses
			.softreg_resp(softreg_resp_to_axil2sr),
			.softreg_resp_grant(softreg_resp_grant_from_axil2sr)
		);
	end
endgenerate

// AmorphOS to apps
SoftRegReq                   app_softreg_req[F1_NUM_APPS-1:0];
SoftRegResp                  app_softreg_resp[F1_NUM_APPS-1:0];		

// MemDrive connectors
AMIRequest                   md_mem_reqs        [1:0];
wire                         md_mem_req_grants  [1:0];
AMIResponse                  md_mem_resps       [1:0];
wire                         md_mem_resp_grants [1:0];
// SimSimpleDRAM connectors
MemReq                       ssd_mem_req_in[1:0];
wire                         ssd_mem_req_grant_out[1:0];
MemResp                      ssd_mem_resp_out[1:0];
logic                        ssd_mem_resp_grant_in[1:0];

// Connect to AmorphOS or test module
generate
	if (F1_CONFIG_SOFTREG_CONFIG == 0) begin : axil2sr_test
	end else if (F1_CONFIG_SOFTREG_CONFIG == 1) begin : axil2sr_memdrive_test
	end else if (F1_CONFIG_SOFTREG_CONFIG == 2) begin
		// Full AmorphOS system
		// SoftReg Interface
		if (F1_AXIL_USE_ROUTE_TREE == 0) begin : sr_no_tree
			AmorphOSSoftReg
			amorphos_softreg_inst
			(
				// User clock and reset
				.clk(global_clk),
				.rst(global_rst), 
				.app_enable(app_enable),
				// Interface to Host
				.softreg_req(softreg_req_from_axil2sr),
				.softreg_resp(softreg_resp_to_axil2sr),
				// Virtualized interface each app
				.app_softreg_req(app_softreg_req),
				.app_softreg_resp(app_softreg_resp)
			);
		end else begin : sr_with_tree
			AmorphOSSoftReg_RouteTree #(.SR_NUM_APPS(F1_NUM_APPS)) amorphos_softreg_inst_route_tree
			(
				// User clock and reset
				.clk(global_clk),
				.rst(global_rst), 
				.app_enable(app_enable),
				// Interface to Host
				.softreg_req(softreg_req_from_axil2sr),
				.softreg_resp(softreg_resp_to_axil2sr),
				// Virtualized interface each app
				.app_softreg_req(app_softreg_req),
				.app_softreg_resp(app_softreg_resp)
			);
		end
		// has to accept it, SW makes sure it isn't swamped
		assign softreg_req_grant_to_axil2sr    = softreg_req_from_axil2sr.valid;
	end // end else

endgenerate

//------------------------------------
// Memory Interfaces
//------------------------------------
// AmorphOS connectors to the apps
AMIRequest                   app_mem_reqs        [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
logic                        app_mem_req_grants  [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
AMIResponse                  app_mem_resps       [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
wire                         app_mem_resp_grants [F1_NUM_APPS-1:0][AMI_NUM_PORTS-1:0];
// AmorphOS connectors to AMI2AXI4
AMIRequest                   ami2_ami2axi4_req_out        [F1_NUM_MEM_CHANNELS-1:0];
wire                         ami2_ami2axi4_req_grant_in   [F1_NUM_MEM_CHANNELS-1:0];
AMIResponse                  ami2_ami2axi4_resp_in        [F1_NUM_MEM_CHANNELS-1:0];
logic                        ami2_ami2axi4_resp_grant_out [F1_NUM_MEM_CHANNELS-1:0];


//------------------------------------
// Apps 
//------------------------------------

generate
	for (app_num = 0; app_num < F1_NUM_APPS; app_num = app_num + 1) begin : multi_inst
		if (F1_CONFIG_APPS == 1) begin : multi_memdrive
		end else if (F1_CONFIG_APPS == 2) begin : multi_dnnweaver
		end else if (F1_CONFIG_APPS == 3) begin : multi_bitcoin
		end else if (F1_CONFIG_APPS == 4) begin : cascade
			CascadeWrapper
			#(
				.app_num(app_num)
			)
			cascade_wrapper_inst
			(
				// User clock and reset
				.clk(global_clk),
				.rst(global_rst),

				// Simplified Memory interface
				.mem_reqs(app_mem_reqs[app_num]),
				.mem_req_grants(app_mem_req_grants[app_num]),
				.mem_resps(app_mem_resps[app_num]),
				.mem_resp_grants(app_mem_resp_grants[app_num]),

				// PCIe Slot DMA interface
				.pcie_packet_in(dummy_pcie_packet),
				.pcie_full_out(),   // unused

				.pcie_packet_out(), // unused
				.pcie_grant_in(1'b0),

				// Soft register interface
				.softreg_req(app_softreg_req[app_num]),
				.softreg_resp(app_softreg_resp[app_num])
			);
		end else if (F1_CONFIG_APPS == 5) begin : multi_dram
			// DRAM SoftReg signal buffering
			SoftRegReq  DRAM_softreg_req_buf;
			logic       DRAM_softreg_req_grant;
			
			SoftRegResp DRAM_softreg_resp_buf[3:0];
			SoftRegResp DRAM_softreg_resp_buf2[3:0];
			SoftRegResp DRAM_softreg_resp_buf3[1:0];
			SoftRegResp DRAM_softreg_resp_buf4;
			SoftRegResp DRAM_softreg_resp;
			logic       DRAM_softreg_resp_grant;
			
			lib_pipe #(.WIDTH($bits(SoftRegReq)), .STAGES(3)) PIPE_DRAM_softreg_req (
				.clk(global_clk),
				.rst_n(global_rst_n),
				.in_bus(app_softreg_req[0]),
				.out_bus(DRAM_softreg_req_buf)
			);

			DRAM_Loopback #(
				.SR_ID(0)
			) DMLb_1 (
				// General signals
				.clk(global_clk),
				.rst(global_rst),
				
				.cl_axi_mstr_bus(cl_axi_mstr_bus[0]),
				
				// SoftReg control interface
				.softreg_req(DRAM_softreg_req_buf),
				.softreg_resp(DRAM_softreg_resp_buf[0])
			);

			DRAM_Loopback #(
				.SR_ID(1)
			) DMLb_2 (
				// General signals
				.clk(global_clk),
				.rst(global_rst),
				
				.cl_axi_mstr_bus(cl_axi_mstr_bus[1]),
				
				// SoftReg control interface
				.softreg_req(DRAM_softreg_req_buf),
				.softreg_resp(DRAM_softreg_resp_buf[1])
			);

			DRAM_Loopback #(
				.SR_ID(2)
			) DMLb_3 (
				// General signals
				.clk(global_clk),
				.rst(global_rst),
				
				.cl_axi_mstr_bus(cl_axi_mstr_bus[2]),
				
				// SoftReg control interface
				.softreg_req(DRAM_softreg_req_buf),
				.softreg_resp(DRAM_softreg_resp_buf[2])
			);

			DRAM_Loopback #(
				.SR_ID(3)
			) DMLb_4 (
				// General signals
				.clk(global_clk),
				.rst(global_rst),
				
				.cl_axi_mstr_bus(cl_axi_mstr_bus[3]),
				
				// SoftReg control interface
				.softreg_req(DRAM_softreg_req_buf),
				.softreg_resp(DRAM_softreg_resp_buf[3])
			);

			always @(posedge global_clk) begin
				if (global_rst_n) begin
					DRAM_softreg_resp_buf2[0] <= DRAM_softreg_resp_buf[0];
					DRAM_softreg_resp_buf2[1] <= DRAM_softreg_resp_buf[1];
					DRAM_softreg_resp_buf2[2] <= DRAM_softreg_resp_buf[2];
					DRAM_softreg_resp_buf2[3] <= DRAM_softreg_resp_buf[3];
					
					DRAM_softreg_resp_buf3[0] <= DRAM_softreg_resp_buf2[0] | DRAM_softreg_resp_buf2[1];
					DRAM_softreg_resp_buf3[1] <= DRAM_softreg_resp_buf2[2] | DRAM_softreg_resp_buf2[3];
					
					DRAM_softreg_resp_buf4 <= DRAM_softreg_resp_buf3[0] | DRAM_softreg_resp_buf3[1];
				end else begin
					DRAM_softreg_resp_buf2[0] <= '0;
					DRAM_softreg_resp_buf2[1] <= '0;
					DRAM_softreg_resp_buf2[2] <= '0;
					DRAM_softreg_resp_buf2[3] <= '0;
					
					DRAM_softreg_resp_buf3[0] <= '0;
					DRAM_softreg_resp_buf3[1] <= '0;
					
					DRAM_softreg_resp_buf4 <= '0;
				end
			end
			assign app_softreg_resp[0] = DRAM_softreg_resp_buf4;
		end else if (F1_CONFIG_APPS == 6) begin : verilog_app
			VerilogWrapper #(
				.app_num(app_num)
			) vw (
				// General signals
				.clk(global_clk),
				.rst(global_rst),
				
				// Virtual memory interface
				.axi_m(cl_axi_mstr_bus[app_num]),
				
				// SoftReg control interface
				.softreg_req(app_softreg_req[app_num]),
				.softreg_resp(app_softreg_resp[app_num])
			);
		end
	end
endgenerate

//------------------------------------
// Misc/Debug Bridge
//------------------------------------
/*
// Outputs need to be assigned
output logic[31:0] cl_sh_status0,           //Functionality TBD
output logic[31:0] cl_sh_status1,           //Functionality TBD
output logic[31:0] cl_sh_id0,               //15:0 - PCI Vendor ID
											//31:16 - PCI Device ID
output logic[31:0] cl_sh_id1,               //15:0 - PCI Subsystem Vendor ID
											//31:16 - PCI Subsystem ID
output logic[15:0] cl_sh_status_vled,       //Virtual LEDs, monitored through FPGA management PF and tools

output logic tdo (for debug)
*/

assign cl_sh_id0[31:0]       = `CL_SH_ID0;
assign cl_sh_id1[31:0]       = `CL_SH_ID1;
assign cl_sh_status0[31:0]   = 32'h0000_0000;
assign cl_sh_status1[31:0]   = 32'h0000_0000;

assign cl_sh_status_vled = 16'h0000;

assign tdo = 1'b0; // TODO: Not really sure what this does since we're not creating a debug bridge

// Counters
//-------------------------------------------------------------
// These are global counters that increment every 4ns.  They
// are synchronized to clk_main_a0.  Note if clk_main_a0 is
// slower than 250MHz, the CL will see skips in the counts
//-------------------------------------------------------------
//input[63:0] sh_cl_glcount0                   //Global counter 0
//input[63:0] sh_cl_glcount1                   //Global counter 1

//------------------------------------
// Tie-Off HMC Interfaces
//------------------------------------
assign hmc_iic_scl_o            =  1'b0;
assign hmc_iic_scl_t            =  1'b0;
assign hmc_iic_sda_o            =  1'b0;
assign hmc_iic_sda_t            =  1'b0;

assign hmc_sh_stat_ack          =  1'b0;
//assign hmc_sh_stat_rdata[31:0]  = 32'b0;
//assign hmc_sh_stat_int[7:0]     =  8'b0;

//------------------------------------
// Tie-Off Aurora Interfaces
//------------------------------------
assign aurora_sh_stat_ack   =  1'b0;
assign aurora_sh_stat_rdata = 32'b0;
assign aurora_sh_stat_int   =  8'b0;

endmodule

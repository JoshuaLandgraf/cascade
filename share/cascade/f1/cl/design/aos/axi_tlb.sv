
// Interface for address translations
interface tlb_bus_t;
	logic [51:0] req_page_num;
	//logic [15:0] req_id;
	logic        req_valid;
	logic        req_ready;
	
	logic [51:0] resp_page_num;
	//logic [15:0] resp_id;
	logic        resp_ok;
	logic        resp_valid;
	logic        resp_ready;
	
	modport master (input req_page_num, req_valid, output req_ready,
	                output resp_page_num, resp_ok, resp_valid, input resp_ready);
	modport slave  (output req_page_num, req_valid, input req_ready,
	                input resp_page_num, resp_ok, resp_valid, output resp_ready);
endinterface

// AXI read channel manager
module read_mgr (
	input clk,
	input rst,
	
	input [15:0] arid_m,
	input [63:0] araddr_m,
	input [7:0]  arlen_m,
	input [2:0]  arsize_m,
	input        arvalid_m,
	output       arready_m,
	
	output [15:0]  rid_m,
	output [511:0] rdata_m,
	output [1:0]   rresp_m,
	output         rlast_m,
	output         rvalid_m,
	input          rready_m,
	
	tlb_bus_t.slave tlb_s,
	axi_bus_t.slave phys_read_s
);
localparam FIFO_LD = 5;

//// accept AXI reads and request address translation
// ar metadata FIFO signals
wire amf_wrreq;
wire [38:0] amf_data;
wire amf_full;
wire [38:0] amf_q;
wire amf_empty;
wire amf_rdreq;

// pg num FIFO signals
wire pnf_wrreq;
wire [51:0] pnf_data;
wire pnf_full;
wire [51:0] pnf_q;
wire pnf_empty;
wire pnf_rdreq;

// output signal assigns
assign arready_m = !amf_full && !pnf_full;
assign tlb_s.req_page_num = pnf_q;
assign tlb_s.req_valid = !pnf_empty;

// ar metadata FIFO assigns
assign amf_wrreq = !pnf_full && arvalid_m;
assign amf_data = {arid_m, arlen_m, arsize_m, araddr_m[11:0]};
//assign amf_rdreq = TODO; // will assign later

// pg num FIFO assigns
assign pnf_wrreq = !amf_full && arvalid_m;
assign pnf_data = araddr_m[63:12];
assign pnf_rdreq = tlb_s.req_ready;

// FIFO instantiations
HullFIFO #(
	.TYPE(3),
	.WIDTH(39),
	.LOG_DEPTH(FIFO_LD)
) ar_metadata_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(amf_wrreq),
	.data(amf_data),
	.full(amf_full),
	.q(amf_q),
	.empty(amf_empty),
	.rdreq(amf_rdreq)
);
HullFIFO #(
	.TYPE(3),
	.WIDTH(52),
	.LOG_DEPTH(FIFO_LD)
) pg_num_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(pnf_wrreq),
	.data(pnf_data),
	.full(pnf_full),
	.q(pnf_q),
	.empty(pnf_empty),
	.rdreq(pnf_rdreq)
);

//// Buffer translation responses
// phys addr FIFO signals
wire paf_wrreq;
wire [52:0] paf_data;
wire paf_full;
wire [52:0] paf_q;
wire paf_empty;
wire paf_rdreq;

// phys addr FIFO assigns
assign paf_wrreq = tlb_s.resp_valid;
assign paf_data = {tlb_s.resp_page_num, tlb_s.resp_ok};
//assign paf_rdreq = TODO; // will assign later

// other assigns
assign tlb_s.resp_ready = !paf_full;

// FIFO instantiation
HullFIFO #(
	.TYPE(3),
	.WIDTH(53),
	.LOG_DEPTH(FIFO_LD)
) phys_addr_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(paf_wrreq),
	.data(paf_data),
	.full(paf_full),
	.q(paf_q),
	.empty(paf_empty),
	.rdreq(paf_rdreq)
);

//// Forward AXI reads if translation ok
// output metadata FIFO signals
wire omf_wrreq;
wire [16:0] omf_data;
wire omf_full;
wire [16:0] omf_q;
wire omf_empty;
wire omf_rdreq;

// assigns
// TODO: add support for re-ordering
assign {phys_read_s.arid, phys_read_s.arlen, phys_read_s.arsize} = {16'h00, amf_q[22:12]};
assign phys_read_s.araddr = {paf_q[52:1], amf_q[11:0]};
assign phys_read_s.arvalid = !omf_full && !amf_empty && !paf_empty && paf_q[0];
assign amf_rdreq = !omf_full && !paf_empty && (paf_q[0] ? phys_read_s.arready : 1'b1);
assign paf_rdreq = !omf_full && !amf_empty && (paf_q[0] ? phys_read_s.arready : 1'b1);

assign omf_wrreq = !amf_empty && !paf_empty && (paf_q[0] ? phys_read_s.arready : 1'b1);
assign omf_data = {amf_q[38:23], paf_q[0]};
//assign omf_rdreq = TODO; // will assign later

// output metadata FIFO instantiation
HullFIFO #(
	.TYPE(3),
	.WIDTH(17),
	.LOG_DEPTH(FIFO_LD)
) output_metadata_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(omf_wrreq),
	.data(omf_data),
	.full(omf_full),
	.q(omf_q),
	.empty(omf_empty),
	.rdreq(omf_rdreq)
);

//// Return read / dummy data
// read return FIFO signals
wire rrf_wrreq;
wire [514:0] rrf_data;
wire rrf_full;
wire [514:0] rrf_q;
wire rrf_empty;
wire rrf_rdreq;

// assigns
assign phys_read_s.rready = !rrf_full;
assign rrf_wrreq = phys_read_s.rvalid;
assign rrf_data = {phys_read_s.rdata, phys_read_s.rresp, phys_read_s.rlast};
assign rrf_rdreq = rready_m && !omf_empty && omf_q[0];
assign omf_rdreq = rready_m && (omf_q[0] ? (!rrf_empty && rrf_q[0]) : 1'b1);

assign rid_m = omf_q[16:1];
assign rdata_m = rrf_q[514:3];
assign rresp_m = omf_q[0] ? rrf_q[2:1] : 2'b10;
assign rlast_m = omf_q[0] ? rrf_q[0] : 1'b1;
assign rvalid_m = !omf_empty && (omf_q[0] ? !rrf_empty : 1'b1);

// read return FIFO instantiation
HullFIFO #(
	.TYPE(3),
	.WIDTH(515),
	.LOG_DEPTH(4)
) read_return_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(rrf_wrreq),
	.data(rrf_data),
	.full(rrf_full),
	.q(rrf_q),
	.empty(rrf_empty),
	.rdreq(rrf_rdreq)
);

endmodule


// AXI write channel manager
module write_mgr (
	input clk,
	input rst,
	
	input [15:0] awid_m,
	input [63:0] awaddr_m,
	input [7:0]  awlen_m,
	input [2:0]  awsize_m,
	input        awvalid_m,
	output       awready_m,
	
	input [15:0]  wid_m,
	input [511:0] wdata_m,
	input [63:0]  wstrb_m,
	input         wlast_m,
	input         wvalid_m,
	output        wready_m,
	
	output [15:0] bid_m,
	output [1:0]  bresp_m,
	output        bvalid_m,
	input         bready_m,
	
	tlb_bus_t.slave tlb_s,
	axi_bus_t.slave phys_write_s
);
localparam FIFO_LD = 5;

//// accept AXI writes and request address translation
// aw metadata FIFO signals
wire amf_wrreq;
wire [38:0] amf_data;
wire amf_full;
wire [38:0] amf_q;
wire amf_empty;
wire amf_rdreq;

// pg num FIFO signals
wire pnf_wrreq;
wire [51:0] pnf_data;
wire pnf_full;
wire [51:0] pnf_q;
wire pnf_empty;
wire pnf_rdreq;

// output signal assigns
assign awready_m = !amf_full && !pnf_full;
assign tlb_s.req_page_num = pnf_q;
assign tlb_s.req_valid = !pnf_empty;

// aw metadata FIFO assigns
assign amf_wrreq = !pnf_full && awvalid_m;
assign amf_data = {awid_m, awlen_m, awsize_m, awaddr_m[11:0]};
//assign amf_rdreq = TODO; // will assign later

// pg num FIFO assigns
assign pnf_wrreq = !amf_full && awvalid_m;
assign pnf_data = awaddr_m[63:12];
assign pnf_rdreq = tlb_s.req_ready;

// FIFO instantiations
HullFIFO #(
	.TYPE(3),
	.WIDTH(39),
	.LOG_DEPTH(FIFO_LD)
) aw_metadata_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(amf_wrreq),
	.data(amf_data),
	.full(amf_full),
	.q(amf_q),
	.empty(amf_empty),
	.rdreq(amf_rdreq)
);
HullFIFO #(
	.TYPE(3),
	.WIDTH(52),
	.LOG_DEPTH(FIFO_LD)
) pg_num_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(pnf_wrreq),
	.data(pnf_data),
	.full(pnf_full),
	.q(pnf_q),
	.empty(pnf_empty),
	.rdreq(pnf_rdreq)
);

//// Buffer translation responses
// phys addr FIFO signals
wire paf_wrreq;
wire [52:0] paf_data;
wire paf_full;
wire [52:0] paf_q;
wire paf_empty;
wire paf_rdreq;

// phys addr FIFO assigns
assign paf_wrreq = tlb_s.resp_valid;
assign paf_data = {tlb_s.resp_page_num, tlb_s.resp_ok};
//assign paf_rdreq = TODO; // will assign later

// other assigns
assign tlb_s.resp_ready = !paf_full;

// FIFO instantiation
HullFIFO #(
	.TYPE(3),
	.WIDTH(53),
	.LOG_DEPTH(FIFO_LD)
) phys_addr_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(paf_wrreq),
	.data(paf_data),
	.full(paf_full),
	.q(paf_q),
	.empty(paf_empty),
	.rdreq(paf_rdreq)
);

//// Forward AXI writes if translation ok
// input metadata FIFO signals
wire imf_wrreq;
wire [16:0] imf_data;
wire imf_full;
wire [16:0] imf_q;
wire imf_empty;
wire imf_rdreq;

// assigns
// TODO: add support for re-ordering
assign {phys_write_s.awid, phys_write_s.awlen, phys_write_s.awsize} = {16'h00, amf_q[22:12]};
assign phys_write_s.awaddr = {paf_q[52:1], amf_q[11:0]};
assign phys_write_s.awvalid = !imf_full && !amf_empty && !paf_empty && paf_q[0];
assign amf_rdreq = !imf_full && !paf_empty && (paf_q[0] ? phys_write_s.awready : 1'b1);
assign paf_rdreq = !imf_full && !amf_empty && (paf_q[0] ? phys_write_s.awready : 1'b1);

assign imf_wrreq = !amf_empty && !paf_empty && (paf_q[0] ? phys_write_s.awready : 1'b1);
assign imf_data = {amf_q[38:23], paf_q[0]};
//assign imf_rdreq = TODO; // will assign later

// input metadata FIFO instantiation
HullFIFO #(
	.TYPE(3),
	.WIDTH(17),
	.LOG_DEPTH(FIFO_LD)
) input_metadata_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(imf_wrreq),
	.data(imf_data),
	.full(imf_full),
	.q(imf_q),
	.empty(imf_empty),
	.rdreq(imf_rdreq)
);

//// Accept and forward write data
// write data FIFO signals
wire wdf_wrreq;
wire [592:0] wdf_data;
wire wdf_full;
wire [592:0] wdf_q;
wire wdf_empty;
wire wdf_rdreq;

// response metadata FIFO signals
wire rmf_wrreq;
wire [16:0] rmf_data;
wire rmf_full;
wire [16:0] rmf_q;
wire rmf_empty;
wire rmf_rdreq;

// assigns
//TODO: add support for reordering
assign phys_write_s.wid = 16'h00;
assign phys_write_s.wdata = wdf_q[576:65];
assign phys_write_s.wstrb = wdf_q[64:1];
assign phys_write_s.wlast = wdf_q[0];
assign phys_write_s.wvalid = !rmf_full && !wdf_empty && !imf_empty && imf_q[0];

assign wready_m = !wdf_full;
assign wdf_wrreq = wvalid_m;
assign wdf_data = {wid_m, wdata_m, wstrb_m, wlast_m};
assign wdf_rdreq = !rmf_full && !imf_empty && (imf_q[0] ? phys_write_s.wready : 1'b1);
assign imf_rdreq = !rmf_full && !wdf_empty && (imf_q[0] ? phys_write_s.wready : 1'b1) && wdf_q[0];

assign rmf_wrreq = !imf_empty && !wdf_empty && (imf_q[0] ? phys_write_s.wready : 1'b1) && wdf_q[0];
assign rmf_data = imf_q;
//assign rmf_rdreq = TODO; // will assign later

// FIFO instantiations
HullFIFO #(
	.TYPE(3),
	.WIDTH(593),
	.LOG_DEPTH(4)
) write_data_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(wdf_wrreq),
	.data(wdf_data),
	.full(wdf_full),
	.q(wdf_q),
	.empty(wdf_empty),
	.rdreq(wdf_rdreq)
);
HullFIFO #(
	.TYPE(3),
	.WIDTH(17),
	.LOG_DEPTH(FIFO_LD)
) response_metadata_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(rmf_wrreq),
	.data(rmf_data),
	.full(rmf_full),
	.q(rmf_q),
	.empty(rmf_empty),
	.rdreq(rmf_rdreq)
);

//// Return write responses
// response data FIFO signals
wire rdf_wrreq;
wire [17:0] rdf_data;
wire rdf_full;
wire [17:0] rdf_q;
wire rdf_empty;
wire rdf_rdreq;

// assigns
assign phys_write_s.bready = !rdf_full;
assign rdf_wrreq = phys_write_s.bvalid;
assign rdf_data = {phys_write_s.bid, phys_write_s.bresp};
assign rdf_rdreq = bready_m && !rmf_empty && rmf_q[0];
assign rmf_rdreq = bready_m && (rmf_q[0] ? !rdf_empty : 1'b1);

assign bid_m = rmf_q[16:1];
assign bresp_m = rmf_q[0] ? rdf_q[1:0] : 2'b10;
assign bvalid_m = !rmf_empty && (rmf_q[0] ? !rdf_empty : 1'b1);

// response data FIFO instantiation
HullFIFO #(
	.TYPE(3),
	.WIDTH(18),
	.LOG_DEPTH(4)
) response_data_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(rdf_wrreq),
	.data(rdf_data),
	.full(rdf_full),
	.q(rdf_q),
	.empty(rdf_empty),
	.rdreq(rdf_rdreq)
);

endmodule

// Multiplexes physical memory channel
module phys_multiplexer (
	input clk,
	input rst,
	
	axi_bus_t.master phys_rm,
	axi_bus_t.master phys_wm,
	axi_bus_t.master phys_tlb,
	
	axi_bus_t.slave phys_s
);

//// Read path
// Interleave read address requests
// Use 1b of rid signal for tracking channels
assign phys_s.arid = phys_tlb.arvalid ? {phys_tlb.arid[14:0], 1'b0} : {phys_rm.arid[14:0], 1'b1};
assign phys_s.araddr = phys_tlb.arvalid ? phys_tlb.araddr : phys_rm.araddr;
assign phys_s.arlen = phys_tlb.arvalid ? phys_tlb.arlen : phys_rm.arlen;
assign phys_s.arsize = phys_tlb.arvalid ? phys_tlb.arsize : phys_rm.arsize;
assign phys_s.arvalid = phys_tlb.arvalid ? 1'b1 : phys_rm.arvalid;
assign phys_tlb.arready = phys_tlb.arvalid ? phys_s.arready : 1'b0;
assign phys_rm.arready = phys_tlb.arvalid ? 1'b0 : phys_s.arready;

assign phys_tlb.rid = {1'b0, phys_s.rid[15:1]};
assign phys_rm.rid = {1'b0, phys_s.rid[15:1]};
assign phys_tlb.rdata = phys_s.rdata;
assign phys_rm.rdata = phys_s.rdata;
assign phys_tlb.rresp = phys_s.rresp;
assign phys_rm.rresp = phys_s.rresp;
assign phys_tlb.rlast = phys_s.rlast;
assign phys_rm.rlast = phys_s.rlast;
assign phys_tlb.rvalid = phys_s.rvalid && (phys_s.rid[0] == 1'b0);
assign phys_rm.rvalid = phys_s.rvalid && (phys_s.rid[0] == 1'b1);
assign phys_s.rready = (phys_s.rid[0] == 1'b0) ? phys_tlb.rready : phys_rm.rready;

//// Write path
// Assume no writes from TLB for now
assign phys_s.awid = phys_wm.awid;
assign phys_s.awaddr = phys_wm.awaddr;
assign phys_s.awlen = phys_wm.awlen;
assign phys_s.awsize = phys_wm.awsize;
assign phys_s.awvalid = phys_wm.awvalid;
assign phys_wm.awready = phys_s.awready;

assign phys_s.wid = phys_wm.wid;
assign phys_s.wdata = phys_wm.wdata;
assign phys_s.wstrb = phys_wm.wstrb;
assign phys_s.wlast = phys_wm.wlast;
assign phys_s.wvalid = phys_wm.wvalid;
assign phys_wm.wready = phys_s.wready;

assign phys_wm.bid = phys_s.bid;
assign phys_wm.bresp = phys_s.bresp;
assign phys_wm.bvalid = phys_s.bvalid;
assign phys_s.bready = phys_wm.bready;

endmodule


// Processes PTEs in TLB
// Entirely combinational
module pte_helper #(
	parameter SR_ID = 0
) (

	input [63:0] pte,
	input [52:0] vpn,
	
	output found,
	output ok,
	output [51:0] rpn
);

wire prsnt_ok = pte[0];	// entry present
wire rw_ok = vpn[0] ? 1'b1 : pte[1];  // entry writable if necessary
wire vpn_ok = vpn[52:1] == {16'h0000, pte[61:26]};  // vpn matches pte
wire id_ok = SR_ID == pte[63:62];  // application ID matches

assign found = prsnt_ok && vpn_ok && id_ok;
assign ok = found ? rw_ok : 1'b0;
assign rpn = found ? {28'h0000000, pte[25:2]} : 52'h0000000000000;

endmodule


// Handles address translation requests
// Fetches relevant data from memory when needed
module tlb_top #(
	parameter SR_ID = 0
) (
	input clk,
	input rst,
	
	tlb_bus_t.master tlb_read,
	tlb_bus_t.master tlb_write,
	
	axi_bus_t.slave  phys_tlb_s,
	
	input  SoftRegReq  sr_req,
	output SoftRegResp sr_resp
);
localparam FIFO_LD = 5;

//// Read / write channel select
reg last_read_sel;
wire read_sel = last_read_sel ? !tlb_write.req_valid : tlb_read.req_valid;
always @(posedge clk) begin
	if (rst) last_read_sel <= 1'b0;
	else     last_read_sel <= read_sel;
end

//// Mux and buffer inputs
// virtual page num FIFO signals
wire vpnf_wrreq;
wire [52:0] vpnf_data;
wire vpnf_full;
wire [52:0] vpnf_q;
wire vpnf_empty;
wire vpnf_rdreq;

// pte addr FIFO signals
wire ptaf_wrreq;
wire [63:0] ptaf_data;
wire ptaf_full;
wire [63:0] ptaf_q;
wire ptaf_empty;
wire ptaf_rdreq;

// assigns
wire in_valid = read_sel ? tlb_read.req_valid : tlb_write.req_valid;
wire [51:0] virt_page_num = read_sel ? tlb_read.req_page_num : tlb_write.req_page_num;
assign tlb_read.req_ready = read_sel && !vpnf_full && !ptaf_full;
assign tlb_write.req_ready = !read_sel && !vpnf_full && !ptaf_full;

assign vpnf_data = {virt_page_num, read_sel};
assign vpnf_wrreq = in_valid && !ptaf_full;
//assign vpnf_rdreq = TODO; // will assign later

assign ptaf_data = {35'h000000000, virt_page_num[22:0], 6'h00};
assign ptaf_wrreq = in_valid && !vpnf_full;
//assign ptaf_rdreq = TODO; // will assign later

// FIFO instantiations
HullFIFO #(
	.TYPE(3),
	.WIDTH(53),
	.LOG_DEPTH(FIFO_LD)
) vpn_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(vpnf_wrreq),
	.data(vpnf_data),
	.full(vpnf_full),
	.q(vpnf_q),
	.empty(vpnf_empty),
	.rdreq(vpnf_rdreq)
);
HullFIFO #(
	.TYPE(3),
	.WIDTH(64),
	.LOG_DEPTH(FIFO_LD)
) pte_addr_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(ptaf_wrreq),
	.data(ptaf_data),
	.full(ptaf_full),
	.q(ptaf_q),
	.empty(ptaf_empty),
	.rdreq(ptaf_rdreq)
);

//// Request PTEs
assign phys_tlb_s.arid = 16'h0000;
assign phys_tlb_s.araddr = ptaf_q;
assign phys_tlb_s.arlen = 8'h00;
assign phys_tlb_s.arsize = 3'b110;
assign phys_tlb_s.arvalid = !ptaf_empty;
assign ptaf_rdreq = phys_tlb_s.arready;

//// Receive PTEs
// PTE FIFO signals
wire ptef_wrreq;
wire [511:0] ptef_data;
wire ptef_full;
wire [511:0] ptef_q;
wire ptef_empty;
wire ptef_rdreq;

// assigns
assign ptef_data = phys_tlb_s.rdata;
assign ptef_wrreq = phys_tlb_s.rvalid;
//assign ptef_rdreq = TODO; // will assign later
assign phys_tlb_s.rready = !ptef_full;

// PTE FIFO instantiation
HullFIFO #(
    .TYPE(3),
    .WIDTH(512),
    .LOG_DEPTH(4)
) pte_fifo (
    .clock(clk),
    .reset_n(~rst),
    .wrreq(ptef_wrreq),
    .data(ptef_data),
    .full(ptef_full),
    .q(ptef_q),
    .empty(ptef_empty),
    .rdreq(ptef_rdreq)
);

//// Process PTEs
reg resp_found [7:0];
reg resp_found_out;
reg resp_ok [7:0];
reg resp_ok_out;
reg [51:0] resp_page_num [7:0];
reg [51:0] resp_page_num_out;

genvar g;
generate
	for (g = 0; g < 8; g += 1) begin: pte_helpers
		pte_helper #(
			.SR_ID(SR_ID)
		) pteh (
			.pte(ptef_q[64*g +: 64]),
			.vpn(vpnf_q),
			.found(resp_found[g]),
			.ok(resp_ok[g]),
			.rpn(resp_page_num[g])
		);
	end
endgenerate

integer i;
always_comb begin
	resp_found_out = resp_found[0];
	resp_ok_out = resp_ok[0];
	resp_page_num_out = resp_page_num[0];
	
	for (i = 1; i < 8; i += 1) begin: pte_merge
		resp_found_out |= resp_found[i];
		resp_ok_out |= resp_ok[i];
		resp_page_num_out |= resp_page_num[i];
	end
end

//// Return results
assign vpnf_rdreq = !ptef_empty && (vpnf_q[0] ? tlb_read.resp_ready : tlb_write.resp_ready);
assign ptef_rdreq = !vpnf_empty && (vpnf_q[0] ? tlb_read.resp_ready : tlb_write.resp_ready);
assign tlb_read.resp_page_num = resp_page_num_out;
assign tlb_write.resp_page_num = resp_page_num_out;
assign tlb_read.resp_ok = resp_ok_out;
assign tlb_write.resp_ok = resp_ok_out;
assign tlb_read.resp_valid = vpnf_q[0] && !vpnf_empty && !ptef_empty;
assign tlb_write.resp_valid = !vpnf_q[0] && !vpnf_empty && !ptef_empty;

endmodule


// AXI Address Translation Module
// Slave interface accepts requests in virtual addresses
// Master interface generates physical memory traffic
module axi_tlb #(
	parameter SR_ID = 0
) (
	input clk,
	input rst,
	
	input  SoftRegReq  sr_req,
	output SoftRegResp sr_resp,
	
	axi_bus_t.master virt_m,
	axi_bus_t.slave  phys_s
);

// Buses
tlb_bus_t tlb_read();
tlb_bus_t tlb_write();

axi_bus_t phys_rm();
axi_bus_t phys_wm();
axi_bus_t phys_tlb();

// Module instantiations
read_mgr rm (
	.clk(clk),
	.rst(rst),
	
	.arid_m   (virt_m.arid),
	.araddr_m (virt_m.araddr),
	.arlen_m  (virt_m.arlen),
	.arsize_m (virt_m.arsize),
	.arvalid_m(virt_m.arvalid),
	.arready_m(virt_m.arready),
	
	.rid_m   (virt_m.rid),
	.rdata_m (virt_m.rdata),
	.rresp_m (virt_m.rresp),
	.rlast_m (virt_m.rlast),
	.rvalid_m(virt_m.rvalid),
	.rready_m(virt_m.rready),
	
	.tlb_s(tlb_read),
	.phys_read_s(phys_rm)
);
write_mgr wm (
	.clk(clk),
	.rst(rst),
	
	.awid_m   (virt_m.awid),
	.awaddr_m (virt_m.awaddr),
	.awlen_m  (virt_m.awlen),
	.awsize_m (virt_m.awsize),
	.awvalid_m(virt_m.awvalid),
	.awready_m(virt_m.awready),
	
	.wid_m   (virt_m.wid),
	.wdata_m (virt_m.wdata),
	.wstrb_m (virt_m.wstrb),
	.wlast_m (virt_m.wlast),
	.wvalid_m(virt_m.wvalid),
	.wready_m(virt_m.wready),
	
	.bid_m   (virt_m.bid),
	.bresp_m (virt_m.bresp),
	.bvalid_m(virt_m.bvalid),
	.bready_m(virt_m.bready),
	
	.tlb_s(tlb_write),
	.phys_write_s(phys_wm)
);
tlb_top #(
	.SR_ID(SR_ID)
) tt (
	.clk(clk),
	.rst(rst),
	
	.tlb_read(tlb_read),
	.tlb_write(tlb_write),
	
	.phys_tlb_s(phys_tlb),
	
	.sr_req(sr_req),
	.sr_resp(sr_resp)
);
phys_multiplexer pm (
	.clk(clk),
	.rst(rst),
	
	.phys_rm(phys_rm),
	.phys_wm(phys_wm),
	.phys_tlb(phys_tlb),
	
	.phys_s(phys_s)
);

endmodule

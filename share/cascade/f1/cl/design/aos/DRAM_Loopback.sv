// Translates DRAM interface from AXI to AOSPacket

import AMITypes::*;
import AOSF1Types::*;

typedef struct packed {
    logic[35:0] addr;
    logic[19:0] len;
    logic[7:0]  id;
} DRAM_Command;

module DRAM_Write #(
	parameter SR_ID = 0
) (
    // General signals
    input clk,
    input rst,
    
    // Write address channel
    output logic[15:0]  cl_axi_mstr_awid,
    output logic[63:0]  cl_axi_mstr_awaddr,
    output logic[7:0]   cl_axi_mstr_awlen,
    output logic[2:0]   cl_axi_mstr_awsize,
    output logic        cl_axi_mstr_awvalid,
    input               cl_axi_mstr_awready,

    // Write data channel
    output logic[511:0] cl_axi_mstr_wdata,
    output logic[63:0]  cl_axi_mstr_wstrb,
    output logic        cl_axi_mstr_wlast,
    output logic        cl_axi_mstr_wvalid,
    input               cl_axi_mstr_wready,

	// Write response channel
    input logic[15:0]   cl_axi_mstr_bid,
    input logic[1:0]    cl_axi_mstr_bresp,
    input logic         cl_axi_mstr_bvalid,
    output logic        cl_axi_mstr_bready,
    
    // SoftReg control interface
    input SoftRegReq    softreg_req,
    output SoftRegResp  softreg_resp,

    // AOSPacket in
    output logic        packet_in_ready,
    input AOSPacket     packet_in
);

typedef struct packed {
    logic[14:0] num;
    logic[7:0]  id;
} NID;

// Command FIFO signals
// Buffer unpacked SoftReg commands
logic cfifo_full;   // not used
logic cfifo_empty;
logic cfifo_wrreq;
logic cfifo_rdreq;
DRAM_Command cfifo_in;
DRAM_Command cfifo_out;

// Length FIFO signals
// Tracks # writes per txn
logic lfifo_full;
logic lfifo_empty;
logic lfifo_wrreq;
logic lfifo_rdreq;
logic[5:0] lfifo_in;
logic[5:0] lfifo_out;

// NID FIFO signals
// Tracks txns per ID
logic nidfifo_full;
logic nidfifo_empty;
logic nidfifo_wrreq;
logic nidfifo_rdreq;
NID nidfifo_in;
NID nidfifo_out;

// Current command
DRAM_Command cmd;
DRAM_Command next_cmd;

// Remaining txns in cmd
logic[14:0] num_txns;
logic[14:0] next_num_txns;

// Remaining writes in txn
logic[5:0] length;
logic[5:0] next_length;

// Remaining responses for ID
NID pending;
NID next_pending;

// Completed ID LIFO shift register
// Holds up to 32 ID responses
// Response: {1'valid, 2'status, 5'id}
logic[255:0] responses;
logic[255:0] next_responses;


// Command buffering
always_comb begin
    DRAM_Command temp_cmd;
    temp_cmd.addr = softreg_req.data[63:28];
    temp_cmd.len = softreg_req.data[27:8];
    temp_cmd.id = softreg_req.data[7:0];
    
    cfifo_wrreq = 0;
    cfifo_in = temp_cmd;
    
    if (softreg_req.valid && softreg_req.isWrite && 
            (softreg_req.addr[5:4] == SR_ID) && (softreg_req.addr[3:0] == 4'h8)) begin
        // differentiate read / write commands by address
        cfifo_wrreq = 1;
    end
end

// Address channel state machine
typedef enum logic[1:0] {
    AWAIT,   // wait for command
    ANID,   // generate NID
    AAXI,   // send AXI request
    ALEN   // send data length
} astate_t;
astate_t astate;
astate_t next_astate;

always_comb begin
    logic[20:0] aligned_len;
    logic[5:0] page_len;
    logic[5:0] temp_len;

    next_astate = astate;
    next_cmd = cmd;
    next_num_txns = num_txns;
    
    cfifo_rdreq = 0;
    
    nidfifo_wrreq = 0;
    aligned_len = cmd.addr[5:0] + cmd.len;
    // 1 less than the actual number of txns so always at least one txn
    nidfifo_in.num = aligned_len[20:6];
    nidfifo_in.id = cmd.id;
    
    page_len = 6'b111111 - cmd.addr[5:0];
    temp_len = (num_txns == 0) ? cmd.len[5:0] : page_len;
    
    cl_axi_mstr_awid = 0;
    cl_axi_mstr_awaddr = {22'h0, cmd.addr, 6'h0};
    cl_axi_mstr_awlen = {2'd0, temp_len};
    cl_axi_mstr_awsize = 3'b110;
    cl_axi_mstr_awvalid = 0;
    
    lfifo_wrreq = 0;
    lfifo_in = temp_len;
    
    case (astate)
    AWAIT: begin
        cfifo_rdreq = 1;
        next_cmd = cfifo_out;
        if (!cfifo_empty) begin
            next_astate = ANID;
        end
    end
    ANID: begin
        nidfifo_wrreq = 1;
        next_num_txns = nidfifo_in.num;
        if (!nidfifo_full) begin
            next_astate = AAXI;
        end
    end
    AAXI: begin
        cl_axi_mstr_awvalid = 1;
        if (cl_axi_mstr_awready) begin
            next_astate = ALEN;
        end
    end
    ALEN: begin
        lfifo_wrreq = 1;
        if (!lfifo_full) begin
            next_num_txns = num_txns - 1;
            next_cmd.addr[35:6] = cmd.addr[35:6] + 1;
            next_cmd.addr[5:0] = 0;
            next_cmd.len = cmd.len - temp_len - 1;
            if (num_txns == 0) begin
                next_astate = AWAIT;
            end else begin
                next_astate = AAXI;
            end
        end
    end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        astate <= AWAIT;
        cmd <= 0;
        num_txns <= 0;
    end else begin
        astate <= next_astate;
        cmd <= next_cmd;
        num_txns <= next_num_txns;
    end
end

// Write data state machine
typedef enum logic[1:0] {
    WIDLE,   // wait for length
    WSEND   // write data
} wstate_t;
wstate_t wstate;
wstate_t next_wstate;

always_comb begin
    next_wstate = wstate;
    next_length = length;
    
    lfifo_rdreq = 0;
    
    cl_axi_mstr_wdata = packet_in.data;
    cl_axi_mstr_wstrb = {64{1'b1}};
    cl_axi_mstr_wlast = (length == 8'h0);
    cl_axi_mstr_wvalid = 0;
    packet_in_ready = 0;
    
    case(wstate)
    WIDLE: begin
        lfifo_rdreq = 1;
        next_length = lfifo_out;
        if (!lfifo_empty) begin
            next_wstate = WSEND;
        end
    end
    WSEND: begin
        cl_axi_mstr_wvalid = packet_in.valid;
        packet_in_ready = cl_axi_mstr_wready;
        if (packet_in.valid && cl_axi_mstr_wready) begin
            next_length = length - 1;
            if (length == 0) begin
                lfifo_rdreq = 1;
                next_length = lfifo_out;
                if (lfifo_empty) begin
                    next_wstate = WIDLE;
                end
            end
        end
    end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        wstate <= WIDLE;
        length <= 0;
    end else begin
        wstate <= next_wstate;
        length <= next_length;
    end
end

// State machine and logic for:
// Write response channel
// Response shift reg
// Softreg response
typedef enum logic[1:0] {
    RIDLE,   // wait for NID
    RWAIT   // wait for last txn, then record ID
} rstate_t;
rstate_t rstate;
rstate_t next_rstate;

always_comb begin
    next_rstate = rstate;
    next_pending = pending;
    next_responses = responses;
    
    nidfifo_rdreq = 0;
    
    cl_axi_mstr_bready = 0;
    
    if (softreg_req.valid && (!softreg_req.isWrite) &&
            (softreg_req.addr[5:4] == SR_ID) && (softreg_req.addr[3:0] == 4'h8)) begin
        next_responses = {64'h0, responses[255:64]};
    end
    
    softreg_resp.valid = softreg_req.valid && (!softreg_req.isWrite) &&
        (softreg_req.addr[5:4] == SR_ID) && (softreg_req.addr[3:0] == 4'h8);
    softreg_resp.data = softreg_resp.valid ? responses[63:0] : 64'h0;
    
    case(rstate)
    RIDLE: begin
        nidfifo_rdreq = 1;
        next_pending = nidfifo_out;
        if (!nidfifo_empty) begin
            next_rstate = RWAIT;
        end
    end
    RWAIT: begin
        cl_axi_mstr_bready = 1;
        if (cl_axi_mstr_bvalid) begin
            next_pending.num = pending.num - 1;
            next_pending.id[6:5] = pending.id[6:5] | cl_axi_mstr_bresp;
            if (pending.num == 0) begin
                next_rstate = RIDLE;
                next_responses = {next_responses[247:0], 1'b1, next_pending.id[6:0]};
            end
        end
    end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        rstate <= RIDLE;
        pending <= 0;
        responses <= 0;
    end else begin
        rstate <= next_rstate;
        pending <= next_pending;
        responses <= next_responses;
    end
end


HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  ($bits(DRAM_Command)),
    .LOG_DEPTH              (5)
)
CmdFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (cfifo_wrreq),
    .data                   (cfifo_in),
    .full                   (cfifo_full),
    .q                      (cfifo_out),
    .empty                  (cfifo_empty),
    .rdreq                  (cfifo_rdreq)
);

HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  (6),
    .LOG_DEPTH              (5)
)
LenFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (lfifo_wrreq),
    .data                   (lfifo_in),
    .full                   (lfifo_full),
    .q                      (lfifo_out),
    .empty                  (lfifo_empty),
    .rdreq                  (lfifo_rdreq)
);

HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  ($bits(NID)),
    .LOG_DEPTH              (5)
)
NIdFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (nidfifo_wrreq),
    .data                   (nidfifo_in),
    .full                   (nidfifo_full),
    .q                      (nidfifo_out),
    .empty                  (nidfifo_empty),
    .rdreq                  (nidfifo_rdreq)
);

endmodule


module DRAM_Read #(
	parameter SR_ID = 0
) (
    // General signals
    input clk,
    input rst,

    // Read address channel
    // Note max 32 outstanding txns are supported, width is larger to allow bits for AXI fabrics
    output logic[15:0]  cl_axi_mstr_arid,
    output logic[63:0]  cl_axi_mstr_araddr,
    output logic[7:0]   cl_axi_mstr_arlen,
    output logic[2:0]   cl_axi_mstr_arsize,
    output logic        cl_axi_mstr_arvalid,
    input               cl_axi_mstr_arready,

    // Read data channel
    input[15:0]         cl_axi_mstr_rid,
    input[511:0]        cl_axi_mstr_rdata,
    input[1:0]          cl_axi_mstr_rresp,
    input               cl_axi_mstr_rlast,
    input               cl_axi_mstr_rvalid,
    output logic        cl_axi_mstr_rready,
    
    // SoftReg control interface
    input SoftRegReq    softreg_req,
    output SoftRegResp  softreg_resp,

    // AOSPacket out
    input logic         packet_out_ready,
    output AOSPacket    packet_out
);

typedef struct packed {
    logic[14:0] num;
    logic[7:0]  id;
} NID;

// Command FIFO signals
// Buffer unpacked SoftReg commands
logic cfifo_full;   // not used
logic cfifo_empty;
logic cfifo_wrreq;
logic cfifo_rdreq;
DRAM_Command cfifo_in;
DRAM_Command cfifo_out;

// NID FIFO signals
// Tracks txns per ID
logic nidfifo_full;
logic nidfifo_empty;
logic nidfifo_wrreq;
logic nidfifo_rdreq;
NID nidfifo_in;
NID nidfifo_out;

// Response FIFO signals
// Buffers txn responses
logic rfifo_full;
logic rfifo_empty;
logic rfifo_wrreq;
logic rfifo_rdreq;
logic[1:0] rfifo_in;
logic[1:0] rfifo_out;

// Current command
DRAM_Command cmd;
DRAM_Command next_cmd;

// Remaining txns in cmd
logic[19:0] num_txns;
logic[19:0] next_num_txns;

// Remaining reads in txn
logic[7:0] length;
logic[7:0] next_length;

// Remaining responses for ID
NID pending;
NID next_pending;

// Completed ID LIFO shift register
// Holds up to 32 responses
// Response: {1'valid, 2'status, 5'id}
logic[255:0] responses;
logic[255:0] next_responses;


// Command buffering
always_comb begin
    DRAM_Command temp_cmd;
    temp_cmd.addr = softreg_req.data[63:28];
    temp_cmd.len = softreg_req.data[27:8];
    temp_cmd.id = softreg_req.data[7:0];
    
    cfifo_wrreq = 0;
    cfifo_in = temp_cmd;
    
    if (softreg_req.valid && softreg_req.isWrite &&
            (softreg_req.addr[5:4] == SR_ID) && (softreg_req.addr[3:0] == 4'h0)) begin
        // differentiate read / write commands by address
        cfifo_wrreq = 1;
    end
end

// Address channel state machine
typedef enum logic[1:0] {
    AWAIT,   // wait for command
    ANID,   // generate NID
    AAXI   // send AXI request
} astate_t;
astate_t astate;
astate_t next_astate;

always_comb begin
    logic[20:0] aligned_len;
    logic[5:0] page_len;
    logic[5:0] temp_len;
    
    next_astate = astate;
    next_cmd = cmd;
    next_num_txns = num_txns;
    
    cfifo_rdreq = 0;
    
    nidfifo_wrreq = 0;
    aligned_len = cmd.addr[5:0] + cmd.len;
    // 1 less than the actual number of txns so always one txn minimum
    nidfifo_in.num = aligned_len[20:6];
    nidfifo_in.id = cmd.id;
    
    page_len = 6'b111111 - cmd.addr[5:0];
    temp_len = (num_txns == 0) ? cmd.len[5:0] : page_len;
    
    cl_axi_mstr_arid = 0;
    cl_axi_mstr_araddr = {22'h0, cmd.addr, 6'h0};
    cl_axi_mstr_arlen = {2'd0, temp_len};
    cl_axi_mstr_arsize = 3'b110;
    cl_axi_mstr_arvalid = 0;
    
    case (astate)
    AWAIT: begin
        cfifo_rdreq = 1;
        next_cmd = cfifo_out;
        if (!cfifo_empty) begin
            next_astate = ANID;
        end
    end
    ANID: begin
        nidfifo_wrreq = 1;
        next_num_txns = nidfifo_in.num;
        if (!nidfifo_full) begin
            next_astate = AAXI;
        end
    end
    AAXI: begin
        cl_axi_mstr_arvalid = 1;
        if (cl_axi_mstr_arready) begin
            next_num_txns = num_txns - 1;
            next_cmd.addr[35:6] = cmd.addr[35:6] + 1;
            next_cmd.addr[5:0] = 0;
            next_cmd.len = cmd.len - temp_len - 1;
            if (num_txns == 0) begin
                next_astate = AWAIT;
            end
        end
    end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        astate <= AWAIT;
        cmd <= 0;
        num_txns <= 0;
    end else begin
        astate <= next_astate;
        cmd <= next_cmd;
        num_txns <= next_num_txns;
    end
end

// Read data channel logic
// Response enqueue logic
always_comb begin
    packet_out.valid = cl_axi_mstr_rvalid && !rfifo_full;
    packet_out.data = cl_axi_mstr_rdata;
    cl_axi_mstr_rready = packet_out_ready && !rfifo_full;
    
    rfifo_wrreq = 0;
    rfifo_in = cl_axi_mstr_rresp;
    if (cl_axi_mstr_rvalid && packet_out_ready && cl_axi_mstr_rlast) begin
        rfifo_wrreq = 1;
    end
end

// State machine and logic for:
// Response shift reg
// Softreg response
typedef enum logic[1:0] {
    RIDLE,   // wait for response
    RWAIT   // wait for last txn, then record ID
} rstate_t;
rstate_t rstate;
rstate_t next_rstate;

always_comb begin
    next_rstate = rstate;
    next_pending = pending;
    next_responses = responses;
    
    nidfifo_rdreq = 0;
    
    rfifo_rdreq = 0;
    
    if (softreg_req.valid && (!softreg_req.isWrite) &&
            (softreg_req.addr[5:4] == SR_ID) && (softreg_req.addr[3:0] == 4'h0)) begin
        next_responses = {64'h0, responses[255:64]};
    end
    
    softreg_resp.valid = softreg_req.valid && (!softreg_req.isWrite) &&
        (softreg_req.addr[5:4] == SR_ID) && (softreg_req.addr[3:0] == 4'h0);
    softreg_resp.data = softreg_resp.valid ? responses[63:0] : 64'h0;
    
    case(rstate)
    RIDLE: begin
        nidfifo_rdreq = 1;
        next_pending = nidfifo_out;
        if (!nidfifo_empty) begin
            next_rstate = RWAIT;
        end
    end
    RWAIT: begin
        rfifo_rdreq = 1;
        if (!rfifo_empty) begin
            next_pending.num = pending.num - 1;
            next_pending.id[6:5] = pending.id[6:5] | rfifo_out;
            if (pending.num == 0) begin
                next_rstate = RIDLE;
                next_responses = {next_responses[247:0], 1'b1, next_pending.id[6:0]};
            end
        end
    end
    endcase
end

always_ff @(posedge clk) begin
    if (rst) begin
        rstate <= RIDLE;
        pending <= 0;
        responses <= 0;
    end else begin
        rstate <= next_rstate;
        pending <= next_pending;
        responses <= next_responses;
    end
end


HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  ($bits(DRAM_Command)),
    .LOG_DEPTH              (5)
)
CommandFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (cfifo_wrreq),
    .data                   (cfifo_in),
    .full                   (cfifo_full),
    .q                      (cfifo_out),
    .empty                  (cfifo_empty),
    .rdreq                  (cfifo_rdreq)
);

HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  ($bits(NID)),
    .LOG_DEPTH              (5)
)
NIdFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (nidfifo_wrreq),
    .data                   (nidfifo_in),
    .full                   (nidfifo_full),
    .q                      (nidfifo_out),
    .empty                  (nidfifo_empty),
    .rdreq                  (nidfifo_rdreq)
);

HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  (2),
    .LOG_DEPTH              (3)
)
RespFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (rfifo_wrreq),
    .data                   (rfifo_in),
    .full                   (rfifo_full),
    .q                      (rfifo_out),
    .empty                  (rfifo_empty),
    .rdreq                  (rfifo_rdreq)
);

endmodule


module DRAM_Loopback #(
	parameter SR_ID = 0
) (
    // General signals
    input clk,
    input rst,
    
    axi_bus_t.slave cl_axi_mstr_bus,
    
    // SoftReg control interface
    input SoftRegReq softreg_req,
    output SoftRegResp softreg_resp
);

// SoftReg write signals
SoftRegReq softreg_req_write;
SoftRegResp softreg_resp_write;

// SoftReg write signals
SoftRegReq softreg_req_read;
SoftRegResp softreg_resp_read;

// AOSPacket write signals
logic packet_out_ready;
AOSPacket packet_out;

// AOSPacket read signals
logic packet_in_ready;
AOSPacket packet_in;

// FIFO signals
logic full;
logic empty;
logic wrreq;
logic rdreq;
AOSPacket data;
AOSPacket q;

// Connection logic
assign softreg_req_write = softreg_req;
assign softreg_req_read = softreg_req;
assign softreg_resp.valid = softreg_resp_write.valid | softreg_resp_read.valid;
assign softreg_resp.data = softreg_resp_write.data | softreg_resp_read.data;
//assign softreg_resp = softreg_resp_write | softreg_resp_read;

assign packet_out_ready = 1;
assign wrreq = packet_out.valid;
assign data = packet_out;

assign rdreq = packet_in_ready;
assign packet_in.valid = 1;
assign packet_in.data = q.data;
assign packet_in.slot = q.slot;

DRAM_Write #(
    .SR_ID(SR_ID)
) DWD (
    // General signals
    .clk(clk),
    .rst(rst),
 
    // Write address channel
    .cl_axi_mstr_awid(cl_axi_mstr_bus.awid),
    .cl_axi_mstr_awaddr(cl_axi_mstr_bus.awaddr),
    .cl_axi_mstr_awlen(cl_axi_mstr_bus.awlen),
    .cl_axi_mstr_awsize(cl_axi_mstr_bus.awsize),
    .cl_axi_mstr_awvalid(cl_axi_mstr_bus.awvalid),
    .cl_axi_mstr_awready(cl_axi_mstr_bus.awready),

    // Write data channel
    .cl_axi_mstr_wdata(cl_axi_mstr_bus.wdata),
    .cl_axi_mstr_wstrb(cl_axi_mstr_bus.wstrb),
    .cl_axi_mstr_wlast(cl_axi_mstr_bus.wlast),
    .cl_axi_mstr_wvalid(cl_axi_mstr_bus.wvalid),
    .cl_axi_mstr_wready(cl_axi_mstr_bus.wready),

    // Write response channel
    .cl_axi_mstr_bid(cl_axi_mstr_bus.bid),
    .cl_axi_mstr_bresp(cl_axi_mstr_bus.bresp),
    .cl_axi_mstr_bvalid(cl_axi_mstr_bus.bvalid),
    .cl_axi_mstr_bready(cl_axi_mstr_bus.bready),
    
    // SoftReg control interface
    .softreg_req(softreg_req_write),
    .softreg_resp(softreg_resp_write),

    // AOSPacket in
    .packet_in_ready(packet_in_ready),
    .packet_in(packet_in)
);

DRAM_Read #(
    .SR_ID(SR_ID)
) DRD (
    // General Signals
    .clk(clk),
    .rst(rst),

    // Read address channel
    .cl_axi_mstr_arid(cl_axi_mstr_bus.arid),
    .cl_axi_mstr_araddr(cl_axi_mstr_bus.araddr),
    .cl_axi_mstr_arlen(cl_axi_mstr_bus.arlen),
    .cl_axi_mstr_arsize(cl_axi_mstr_bus.arsize),
    .cl_axi_mstr_arvalid(cl_axi_mstr_bus.arvalid),
    .cl_axi_mstr_arready(cl_axi_mstr_bus.arready),

    // Read data channel
    .cl_axi_mstr_rid(cl_axi_mstr_bus.rid),
    .cl_axi_mstr_rdata(cl_axi_mstr_bus.rdata),
    .cl_axi_mstr_rresp(cl_axi_mstr_bus.rresp),
    .cl_axi_mstr_rlast(cl_axi_mstr_bus.rlast),
    .cl_axi_mstr_rvalid(cl_axi_mstr_bus.rvalid),
    .cl_axi_mstr_rready(cl_axi_mstr_bus.rready),
    
    // SoftReg control interface
    .softreg_req(softreg_req_read),
    .softreg_resp(softreg_resp_read),

    // AOSPacket out
    .packet_out_ready(packet_out_ready),
    .packet_out(packet_out)
);

HullFIFO
#(
    .TYPE                   (0),
    .WIDTH                  ($bits(AOSPacket)),
    .LOG_DEPTH              (6)
)
AOSPacketFIFO
(
    .clock                  (clk),
    .reset_n                (~rst),
    .wrreq                  (wrreq),
    .data                   (data),
    .full                   (full),
    .q                      (q),
    .empty                  (empty),
    .rdreq                  (rdreq)
);

endmodule

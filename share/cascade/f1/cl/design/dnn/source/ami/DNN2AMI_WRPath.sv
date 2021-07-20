//`timescale 1ns/1ps
//`include "common.vh" // TODO: Uncomment when not testing
import ShellTypes::*;
import AMITypes::*;

module DNN2AMI_WRPath
#(
 parameter integer NUM_PU               = 2,

  parameter integer AXI_ID               = 0,

  parameter integer TID_WIDTH            = 6,
  parameter integer AXI_ADDR_WIDTH       = 32,
  parameter integer AXI_DATA_WIDTH       = 64,
  parameter integer AWUSER_W             = 1,
  parameter integer ARUSER_W             = 1,
  parameter integer WUSER_W              = 1,
  parameter integer RUSER_W              = 1,
  parameter integer BUSER_W              = 1,

  /* Disabling these parameters will remove any throttling.
   The resulting ERROR flag will not be useful */
  parameter integer C_M_AXI_SUPPORTS_WRITE             = 1,
  parameter integer C_M_AXI_SUPPORTS_READ              = 1,

  /* Max count of written but not yet read bursts.
   If the interconnect/slave is able to accept enough
   addresses and the read channels are stalled, the
   master will issue this many commands ahead of
   write responses */

  // Base address of targeted slave
  //Changing read and write addresses
  parameter         C_M_AXI_READ_TARGET                = 32'hFFFF0000,
  parameter         C_M_AXI_WRITE_TARGET               = 32'hFFFF8000,

  // CUSTOM PARAMS
  parameter         TX_SIZE_WIDTH                      = 10,

  // Number of address bits to test before wrapping
  parameter integer C_OFFSET_WIDTH                     = TX_SIZE_WIDTH,
 
  parameter integer WSTRB_W  = AXI_DATA_WIDTH/8,
  parameter integer NUM_PU_W = $clog2(NUM_PU)+1,
  parameter integer OUTBUF_DATA_W = NUM_PU * AXI_DATA_WIDTH
 
)
(
	// General signals
	input                               clk,
    input                               rst,

	// Connection to rest of memory system
	output logic                        reqValid,
	input                               reqOut_grant,

	// Writes
	// WRITE from BRAM to DDR
	input  wire  [ NUM_PU               -1 : 0 ]        outbuf_empty, // no data in the output buffer
	input  wire  [ OUTBUF_DATA_W        -1 : 0 ]        data_from_outbuf,  // data to write from, portion per PU
	input  wire  [ NUM_PU               -1 : 0 ]        write_valid,       // value is ready to be written back
	output logic   [ NUM_PU               -1 : 0 ]        outbuf_pop,   // dequeue a data item, why is this registered?
	
	// Memory Controller Interface - Write
	input  wire                                         wr_req,   // assert when submitting a wr request
	input  wire  [ NUM_PU_W             -1 : 0 ]        wr_pu_id, // determine where to write, I assume ach PU has a different region to write
	input  wire  [ TX_SIZE_WIDTH        -1 : 0 ]        wr_req_size, // size of request in bytes (I assume)
	input  wire  [ AXI_ADDR_WIDTH       -1 : 0 ]        wr_addr, // address to write to, look like 32 bit addresses
	output reg                                          wr_ready, // ready for more writes
	output reg                                          wr_done,  // no writes left to submit
	output AMIRequest                   reqOut
);
	localparam AMI2DNN_MACRO_WR_Q_DEPTH = 9;
	localparam AMI2DNN_WR_REQ_Q_DEPTH = 9;
	
	genvar pu_num;

	// rename the inputs from the write buffer
	wire[AXI_DATA_WIDTH-1:0] pu_outbuf_data[NUM_PU-1:0];
	generate
		for (pu_num = 0; pu_num < NUM_PU; pu_num = pu_num + 1) begin : per_pu_buf_rename
			assign pu_outbuf_data[pu_num] = data_from_outbuf[((pu_num+1)*AXI_DATA_WIDTH)-1:(pu_num*AXI_DATA_WIDTH)];
		end
	endgenerate	
	
	// Counter for time  stamps
	wire[63:0] current_timestamp;
	Counter64
	time_stamp_counter
	(
		.clk (clk),
		.rst (rst), 
		.increment (1'b1),
		.count (current_timestamp)
	);	
	
	// Queue to buffer Write requests
	wire             macroWrQ_empty;
	wire             macroWrQ_full;
	logic            macroWrQ_enq;
	logic            macroWrQ_deq;
	DNNWeaverMemReq  macroWrQ_in;
	DNNWeaverMemReq  macroWrQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_macroWriteQ
			SoftFIFO
			#(
				.WIDTH					($bits(DNNWeaverMemReq)),
				.LOG_DEPTH				(AMI2DNN_MACRO_WR_Q_DEPTH)
			)
			macroWriteQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(macroWrQ_enq),
				.data                   (macroWrQ_in),
				.full                   (macroWrQ_full),
				.q                      (macroWrQ_out),
				.empty                  (macroWrQ_empty),
				.rdreq                  (macroWrQ_deq)
			);	
		end else begin : FIFO_macroWriteQ
			FIFO
			#(
				.WIDTH					($bits(DNNWeaverMemReq)),
				.LOG_DEPTH				(AMI2DNN_MACRO_WR_Q_DEPTH)
			)
			macroWriteQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(macroWrQ_enq),
				.data                   (macroWrQ_in),
				.full                   (macroWrQ_full),
				.q                      (macroWrQ_out),
				.empty                  (macroWrQ_empty),
				.rdreq                  (macroWrQ_deq)
			);	
		end
	endgenerate	

	// Inputs to the MacroWriteQ
	assign macroWrQ_in  = '{valid: wr_req, isWrite: 1'b1, addr: wr_addr, size: wr_req_size, pu_id: wr_pu_id, time_stamp: current_timestamp};
	assign macroWrQ_enq = wr_req && !macroWrQ_full;		

	// Debug
	always@(posedge clk) begin
		if (macroWrQ_enq) begin
			$display("DNN2AMI:============================================================ Accepting macro WRITE request ADDR: %h Size: %d ",wr_addr,wr_req_size);
		end
		if (wr_req) begin
			$display("DNN2AMI: WR_req is being asserted");
		end	
	end	
	
	// reqOut queue to simplify the sequencing logic
	wire             reqQ_empty;
	wire             reqQ_full;
	logic            reqQ_enq;
	logic            reqQ_deq;
	AMIRequest       reqQ_in;
	AMIRequest       reqQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_reqQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(AMI2DNN_WR_REQ_Q_DEPTH)
			)
			reqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqQ_enq),
				.data                   (reqQ_in),
				.full                   (reqQ_full),
				.q                      (reqQ_out),
				.empty                  (reqQ_empty),
				.rdreq                  (reqQ_deq)
			);	
		end else begin : FIFO_reqQ
			FIFO
			#(
				.WIDTH					($bits(AMIRequest)),
				.LOG_DEPTH				(AMI2DNN_WR_REQ_Q_DEPTH)
			)
			reqQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(reqQ_enq),
				.data                   (reqQ_in),
				.full                   (reqQ_full),
				.q                      (reqQ_out),
				.empty                  (reqQ_empty),
				.rdreq                  (reqQ_deq)
			);	
		end
	endgenerate		
		
	// Interface to the memory system
	assign reqValid = reqQ_out.valid && !reqQ_empty;
	assign reqOut   = reqQ_out;
	assign reqQ_deq = reqOut_grant && reqValid;
	/*
	always@(posedge clk) begin
		if  (reqValid) begin
			$display("                                                       WR PATH: Req valid and size of reqQ is %d, grant: %d, reqQ_deq:  %d", SoftFIFO_reqQ.reqQ.counter,reqOut_grant,reqQ_deq);
		end
	end
	*/
	//assign wr_ready = 1'b1;//macroWrQ_empty && (macro_req_active ? !current_isWrite : 1'b1);// no pending writes?
	//assign wr_done  = 1'b0; // probably not correct
	
	// Two important output signals
	reg wr_ready_reg;
	reg wr_done_reg;

	logic new_wr_ready_reg;
	logic new_wr_done_reg;
	
	// Sequencer logic
	// Arbiter
	logic accept_new_active_req;
	DNNWeaverMemReq macro_arbiter_output;

	always_comb begin
		macroWrQ_deq = 1'b0;
		macro_arbiter_output = macroWrQ_out;
		if (accept_new_active_req) begin
			if (!macroWrQ_empty) begin
				// select Read
				macroWrQ_deq = 1'b1;
				macro_arbiter_output = macroWrQ_out;
			end
		end
	end
	
	// Current macro request being sequenced (fractured into smaller operations)
	reg macro_req_active;
	reg[AXI_ADDR_WIDTH-1:0] current_address;
	reg[TX_SIZE_WIDTH-1:0]  requests_left;
	reg                     current_isWrite;
	reg[NUM_PU_W-1:0]       current_pu_id;

	logic new_macro_req_active;
	logic[AXI_ADDR_WIDTH-1:0] new_current_address;
	logic[TX_SIZE_WIDTH-1:0]  new_requests_left;
	logic                     new_current_isWrite;
	logic[NUM_PU_W-1:0]       new_current_pu_id;
	
	always@(posedge clk) begin
		if (rst) begin
			macro_req_active <= 1'b0;
			current_address  <= 0;
			requests_left    <= 0;
			current_isWrite  <= 1'b0;
			current_pu_id    <= 0;
		end else begin
			macro_req_active <= new_macro_req_active;
			current_address  <= new_current_address;
			requests_left    <= new_requests_left;
			current_isWrite  <= new_current_isWrite;
			current_pu_id    <= new_current_pu_id;
		end
	end

	assign wr_ready = (macroWrQ_empty && !macro_req_active && reqQ_empty);//wr_ready_reg;
	assign wr_done  = wr_done_reg;
	
	always_comb begin
		accept_new_active_req = 1'b0;
		new_macro_req_active  = macro_req_active;
		new_current_address   = current_address;
		new_requests_left     = requests_left;
		new_current_isWrite   = current_isWrite;
		new_current_pu_id     = current_pu_id;

		new_wr_ready_reg = (macroWrQ_empty && !macro_req_active && reqQ_empty);
		new_wr_done_reg  = 1'b0;
	
		reqQ_enq = 1'b0;
	    reqQ_in  = '{valid: 1'b0, isWrite: 1'b1, addr: {{32{1'b0}},current_address} , data: pu_outbuf_data[current_pu_id], size: 8}; // double check this size
	
		for (int i = 0; i < NUM_PU; i = i + 1) begin
			outbuf_pop[i] = 1'b0;
		end

		// An operation is being sequenced
		if (macro_req_active) begin
			// issue write requests
			if (current_isWrite == 1'b1) begin
				if (!outbuf_empty[current_pu_id] && !reqQ_full) begin // TODO: Not sure about this write_valid signal
					outbuf_pop[current_pu_id] = 1'b1;
					reqQ_in  = '{valid: 1'b1, isWrite: 1'b1, addr: {{32{1'b0}},current_address} , data: pu_outbuf_data[current_pu_id], size: 8}; // double check this size
					reqQ_enq = 1'b1;
					new_current_address = current_address + 8; // 8 bytes
					new_requests_left   = requests_left - 1;
				end
			end
			// check if anything is left to issue
			if (new_requests_left == 0) begin
				new_macro_req_active = 1'b0;
				new_wr_done_reg = 1'b1;
			end
		end else begin
			// See if there is a new operation available
			if (!macroWrQ_empty) begin
				// A new operation can become active
				accept_new_active_req = 1'b1;
				new_macro_req_active  = 1'b1;
				// Select the output of the arbiter
				new_current_address = macro_arbiter_output.addr;
				new_requests_left   = macro_arbiter_output.size;
				new_current_isWrite = macro_arbiter_output.isWrite;
				new_current_pu_id   = macro_arbiter_output.pu_id;
			end
		end
	end
/*
	always@(posedge clk) begin
		if (wr_ready && !wr_done) begin
			$display("DNN2: XXXXXXXXXXXX Should be able to accept a new write XXXXXXXXXXXXXXX");
		end
	end
	
	always@(posedge clk) begin
		if (!outbuf_empty[0] && !outbuf_pop[0]) begin
			$display("WRPATH: Should be popping but we're not ");
		end
		if (outbuf_pop[0]) begin
			$display("WRPATH:                                                                             Popping outbuf data, current addr: %x , %d requests left", new_current_address, new_requests_left);
		end
	end
*/
	always@(posedge clk) begin
		//if (!outbuf_empty[0]) begin
		//	$display("WRPATH: outbuf_empty %d write_valid: %d, reqQ_full %d requests_left %d, current addr: %x",outbuf_empty[0],write_valid[0],reqQ_full, requests_left,current_address);
		//end
	end

	// How the memory controller determines if a wr_request should be sent
	// assign wr_req = !wr_done && (wr_ready) && wr_state == WR_BUSY; //stream_wr_count_inc;
	//  wr_ready <= pu_wr_ready[wr_pu_id] && !(wr_req && wr_ready);
	// We issue a write for a PU when the PU has no writes remaining.
	// WR_DONE is asserted when all the PUs no writes remaining.
	always@(posedge clk) begin
		if (rst) begin
			wr_ready_reg <= 1'b1;
			wr_done_reg  <= 1'b0;
		end else begin
			wr_ready_reg <= new_wr_ready_reg;
			wr_done_reg  <= new_wr_done_reg;
		end
	end
	
endmodule

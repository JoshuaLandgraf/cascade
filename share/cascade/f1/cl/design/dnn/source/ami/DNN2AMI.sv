//`timescale 1ns/1ps
//`include "common.vh" // TODO: Uncomment when not testing
import ShellTypes::*;
import AMITypes::*;

module DNN2AMI
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
    input                               clk,
    input                               rst,

	// AMI signals
    output AMIRequest                   mem_req        ,
    input                               mem_req_grant  ,
	input  AMIResponse                  mem_resp       ,
	output                              mem_resp_grant ,

	// Reads
	// READ from DDR to BRAM
	input  wire                                         inbuf_full, // can the buffer accept new data
	output wire  [ AXI_DATA_WIDTH       -1 : 0 ]        data_to_inbuf, // data to be written
	output wire                                         inbuf_push, // write the data

	// Memory Controller Interface - Read
	input  wire                                         rd_req, // read request
	input  wire  [ TX_SIZE_WIDTH        -1 : 0 ]        rd_req_size, // size of the read request in bytes
	input  wire  [ AXI_ADDR_WIDTH       -1 : 0 ]        rd_addr,     // address of the read request
	output wire                                         rd_ready, // able to accept a new read

	// Writes
	// WRITE from BRAM to DDR
	input  wire  [ NUM_PU               -1 : 0 ]        outbuf_empty, // no data in the output buffer
	input  wire  [ OUTBUF_DATA_W        -1 : 0 ]        data_from_outbuf,  // data to write from, portion per PU
	input  wire  [ NUM_PU               -1 : 0 ]        write_valid,       // value is ready to be written back
	output reg   [ NUM_PU               -1 : 0 ]        outbuf_pop,   // dequeue a data item
	
	// Memory Controller Interface - Write
	input  wire                                         wr_req,   // assert when submitting a wr request
	input  wire  [ NUM_PU_W             -1 : 0 ]        wr_pu_id, // determine where to write, I assume ach PU has a different region to write
	input  wire  [ TX_SIZE_WIDTH        -1 : 0 ]        wr_req_size, // size of request in bytes (I assume)
	input  wire  [ AXI_ADDR_WIDTH       -1 : 0 ]        wr_addr, // address to write to, look like 32 bit addresses
	output reg                                          wr_ready, // ready for more writes
	output reg                                          wr_done  // no writes left to submit

);

	localparam AMI2DNN_MACRO_RD_Q_DEPTH   = 9;
	localparam AMI2DNN_REQ_Q_DEPTH        = 9;
	localparam AMI2DNN_RESP_IN_Q_DEPTH    = 9;
	localparam AMI2DNN_READ_TAG_Q_DEPTH   = 9;

	AMIRequest reqWrPath;
	logic reqWrPath_grant;
	wire wrReqValid;
	
	// Instantiate Write path
	DNN2AMI_WRPath
	#(
		.NUM_PU(NUM_PU),
		.AXI_ID(AXI_ID),
		.TID_WIDTH(TID_WIDTH),
		.AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
		.AXI_DATA_WIDTH (AXI_DATA_WIDTH),
		.AWUSER_W(AWUSER_W),
		.ARUSER_W(ARUSER_W),
		.WUSER_W(WUSER_W),
		.RUSER_W(RUSER_W),
		.BUSER_W(BUSER_W),
		.C_M_AXI_SUPPORTS_WRITE(C_M_AXI_SUPPORTS_WRITE),
		.C_M_AXI_SUPPORTS_READ(C_M_AXI_SUPPORTS_READ),
		.C_M_AXI_READ_TARGET(C_M_AXI_READ_TARGET),
		.C_M_AXI_WRITE_TARGET(C_M_AXI_WRITE_TARGET),
		.TX_SIZE_WIDTH(TX_SIZE_WIDTH),
		.C_OFFSET_WIDTH(C_OFFSET_WIDTH),
		.WSTRB_W(WSTRB_W),
		.NUM_PU_W(NUM_PU_W),
		.OUTBUF_DATA_W(OUTBUF_DATA_W)
	)
	wrPath_inst
	(
		// General signals
		.clk (clk),
		.rst (rst),

		// Connection to rest of memory system
		.reqValid(wrReqValid),
		.reqOut_grant(reqWrPath_grant),

		// Writes
		// WRITE from BRAM to DDR
		.outbuf_empty(outbuf_empty), // no data in the output buffer
		.data_from_outbuf(data_from_outbuf),  // data to write from, portion per PU
		.write_valid(write_valid),       // value is ready to be written back
		.outbuf_pop(outbuf_pop),   // dequeue a data item
		
		// Memory Controller Interface - Write
		.wr_req(wr_req),   // assert when submitting a wr request
		.wr_pu_id(wr_pu_id), // determine where to write, I assume ach PU has a different region to write
		.wr_req_size(wr_req_size), // size of request in bytes (I assume)
		.wr_addr(wr_addr), // address to write to, look like 32 bit addresses
		.wr_ready(wr_ready), // ready for more writes
		.wr_done(wr_done),  // no writes left to submit
		.reqOut(reqWrPath)
	);

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
	
	// Queue to buffer Read requests
	wire             macroRdQ_empty;
	wire             macroRdQ_full;
	logic            macroRdQ_enq;
	logic            macroRdQ_deq;
	DNNWeaverMemReq  macroRdQ_in;
	DNNWeaverMemReq  macroRdQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_macroReadQ
			SoftFIFO
			#(
				.WIDTH					($bits(DNNWeaverMemReq)),
				.LOG_DEPTH				(AMI2DNN_MACRO_RD_Q_DEPTH)
			)
			macroReadQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(macroRdQ_enq),
				.data                   (macroRdQ_in),
				.full                   (macroRdQ_full),
				.q                      (macroRdQ_out),
				.empty                  (macroRdQ_empty),
				.rdreq                  (macroRdQ_deq)
			);	
		end else begin : FIFO_macroReadQ
			FIFO
			#(
				.WIDTH					($bits(DNNWeaverMemReq)),
				.LOG_DEPTH				(AMI2DNN_MACRO_RD_Q_DEPTH)
			)
			macroReadQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(macroRdQ_enq),
				.data                   (macroRdQ_in),
				.full                   (macroRdQ_full),
				.q                      (macroRdQ_out),
				.empty                  (macroRdQ_empty),
				.rdreq                  (macroRdQ_deq)
			);	
		end
	endgenerate

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
				.LOG_DEPTH				(AMI2DNN_REQ_Q_DEPTH)
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
				.LOG_DEPTH				(AMI2DNN_REQ_Q_DEPTH)
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

	// Tag queue to correctly order reads by port 
	wire             tagQ_empty;
	wire             tagQ_full;
	logic            tagQ_enq;
	logic            tagQ_deq;
	DNNMicroRdTag    tagQ_in;
	DNNMicroRdTag    tagQ_out;

	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_readtagQ
			SoftFIFO
			#(
				.WIDTH					($bits(DNNMicroRdTag)),
				.LOG_DEPTH				(AMI2DNN_READ_TAG_Q_DEPTH)
			)
			readtagQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(tagQ_enq),
				.data                   (tagQ_in),
				.full                   (tagQ_full),
				.q                      (tagQ_out),
				.empty                  (tagQ_empty),
				.rdreq                  (tagQ_deq)
			);	
		end else begin : FIFO_readtagQ
			FIFO
			#(
				.WIDTH					($bits(DNNMicroRdTag)),
				.LOG_DEPTH				(AMI2DNN_READ_TAG_Q_DEPTH)
			)
			readtagQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(tagQ_enq),
				.data                   (tagQ_in),
				.full                   (tagQ_full),
				.q                      (tagQ_out),
				.empty                  (tagQ_empty),
				.rdreq                  (tagQ_deq)
			);	
		end
	endgenerate	
	
	// Response path for reads
	wire             respQ_empty;
	wire             respQ_full;
	logic            respQ_enq;
	logic            respQ_deq;
	AMIResponse      respQ_in;
	AMIResponse      respQ_out;	
	
	generate
		if (USE_SOFT_FIFO) begin : SoftFIFO_respQ
			SoftFIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(AMI2DNN_RESP_IN_Q_DEPTH)
			)
			respQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respQ_enq),
				.data                   (respQ_in),
				.full                   (respQ_full),
				.q                      (respQ_out),
				.empty                  (respQ_empty),
				.rdreq                  (respQ_deq)
			);
		end else begin : FIFO_respQ
			FIFO
			#(
				.WIDTH					($bits(AMIResponse)),
				.LOG_DEPTH				(AMI2DNN_RESP_IN_Q_DEPTH)
			)
			respQ
			(
				.clock					(clk),
				.reset_n				(~rst),
				.wrreq					(respQ_enq),
				.data                   (respQ_in),
				.full                   (respQ_full),
				.q                      (respQ_out),
				.empty                  (respQ_empty),
				.rdreq                  (respQ_deq)
			);
		end
	endgenerate

	// Inputs to the MacroReadQ
	assign macroRdQ_in  = '{valid: rd_req, isWrite: 1'b0, addr: rd_addr , size: rd_req_size, pu_id: 0, time_stamp: current_timestamp};
	assign macroRdQ_enq = rd_req && !macroRdQ_full; // no back pressure mechanism, so assume its never full

	// Accept responses from the block buffer
	assign respQ_in  = mem_resp;
	assign respQ_enq = mem_resp.valid && !respQ_full;
	assign mem_resp_grant = respQ_enq;
	
	// Merge responses from the read tag queue and the response queue
	// and push them onto the inBuf
	wire   merge_possible;
	assign merge_possible = !inbuf_full && (tagQ_out.valid && !tagQ_empty) && (respQ_out.valid && !respQ_empty);
	assign inbuf_push     = merge_possible;
	assign tagQ_deq       = merge_possible;
	assign respQ_deq      = merge_possible;
	assign data_to_inbuf  = respQ_out.data[AXI_DATA_WIDTH-1:0];
	
	// debug signals
	always@(posedge clk) begin
		if (macroRdQ_enq) begin
			$display("DNN2AMI:============================================================ Accepting macro READ request ADDR: %h Size: %d ",rd_addr,rd_req_size);
		end
	end
/*
	always@(posedge clk) begin
		if (inbuf_full) begin
			if ((tagQ_out.valid && !tagQ_empty) && (respQ_out.valid && !respQ_empty)) begin
				$display("DNN2AMI::                                             inBuf is full AND data is ready to write into it");
			end else begin
				$display("DNN2AMI:                                              inBuf is full");
			end
		end
		
		if (merge_possible) begin
			$display("DNN2AMI: Filling inBuf Size: %d",respQ_out.size);
		end
			
	end
*/
/*
	// Block Buffer interface
	// Responses
	always@(posedge clk) begin
		if (respQ_enq) begin
			$display("DNN2AMI: Receiving response back from the BlockBuffer Size: %d",respQ_in.size);
		end
	end
	
	// Requests
	
	always@(posedge clk) begin
		if (reqQ_enq) begin
			$display("DNN2AMI: Queuing request to BB, addr: %h, size: %d isWrite: %h Valid: %h", reqQ_in.addr, reqQ_in.size, reqQ_in.isWrite, reqQ_in.valid);
		end	
	end
		
	always@(posedge clk) begin
		if (reqQ_deq) begin
			$display("DNN2AMI: BlockBuffer accepting request.");
		end
	end
*/
	// Sequencer
	// Outputs:
	// reqQ_in
	// reqQ_enq
	// tagQ_enq
	// tagQ_in
	// macroRdQ_deq
	// macroWrQ_deq
	// outbuf_pop
	// Inputs:
	// macroRdQ_out
	// macroWrQ_out
	// mem_req_grant
	// outbuf_empty
	// data_from_outbuf
	// reqQ_full
	
	// Arbiter
	logic accept_new_active_req;
	DNNWeaverMemReq macro_arbiter_output;

	always_comb begin
		macroRdQ_deq = 1'b0;
		macro_arbiter_output = macroRdQ_out;
		if (accept_new_active_req) begin
			if (!macroRdQ_empty) begin
				// select Read
				macroRdQ_deq = 1'b1;
				macro_arbiter_output = macroRdQ_out;
			end
		end
		/*macroRdQ_deq = 1'b0;
		macroWrQ_deq = 1'b0;
		macro_arbiter_output = macroRdQ_out;
		if (accept_new_active_req) begin
			if (!macroRdQ_empty && !macroWrQ_empty) begin
				// Where arbitration actually takes place
				if (macroRdQ_out.time_stamp > macroWrQ_out.time_stamp) begin
					// Select Read
					macroRdQ_deq = 1'b1;
					macro_arbiter_output = macroRdQ_out;
				end else begin
					// Select Write
					macroWrQ_deq = 1'b1;
					macro_arbiter_output = macroWrQ_out;
				end
			end else if (!macroRdQ_empty) begin
				// Select Read
				macroRdQ_deq = 1'b1;
				macro_arbiter_output = macroRdQ_out;
			end else if (!macroWrQ_empty) begin
				// Select Write
				macroWrQ_deq = 1'b1;
				macro_arbiter_output = macroWrQ_out;
			end
		end
		*/
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

	always_comb begin
		accept_new_active_req = 1'b0;
		new_macro_req_active  = macro_req_active;
		new_current_address   = current_address;
		new_requests_left     = requests_left;
		new_current_isWrite   = current_isWrite;
		new_current_pu_id     = current_pu_id;
		tagQ_enq              = 1'b0;
		tagQ_in               = '{valid: 0, addr: 0, size: 0};
		reqQ_in               = '{valid: 0, isWrite: 1'b0, addr: 0 , data: 512'b0, size: 64};;
		reqQ_enq              = 1'b0;
		
		/*
		for (int i = 0; i < NUM_PU; i = i + 1) begin
			outbuf_pop[i] = 1'b0;
		end
		*/

		// An operation is being sequenced
		if (macro_req_active) begin
			// issue write requests
			if (current_isWrite == 1'b1) begin
				if (!outbuf_empty[current_pu_id] && write_valid) begin // TODO: Not sure about this write_valid signal
					$display("DNN2AMI: ZZZZZZZZZZZZZZ THIS SHOULD NEVER EXECUTE ZZZZZZZZZZZZZZZZZZZZZ");
					//outbuf_pop[current_pu_id] = 1'b1;
					//reqQ_in  = '{valid: 1'b1, isWrite: 1'b1, addr: {{32{1'b0}},current_address} , data: pu_outbuf_data[current_pu_id], size: 8}; // double check this size
					reqQ_enq = 1'b1;
					new_current_address = current_address + 8; // 8 bytes
					new_requests_left   = requests_left - 1;
				end
			end else begin 
			// issue read requests
			// tag queue and request queue need to have room
				if (!tagQ_full && !reqQ_full) begin
					tagQ_in  = '{valid: 1'b1, addr: {{32{1'b0}},current_address}, size: 8}; // size here is in bytes
					tagQ_enq = 1'b1;
					reqQ_in  = '{valid: 1'b1, isWrite: 1'b0, addr: {{32{1'b0}},current_address} , data: 512'b0, size: 8}; // double check this size
					reqQ_enq = 1'b1;
					new_current_address = current_address + 8; // 8 bytes
					new_requests_left   = requests_left - 1;
				end
			end
			// check if anything is left to issue
			if (new_requests_left == 0) begin
				new_macro_req_active = 1'b0;
			end
		end else begin
			// See if there is a new operation available
			if (!macroRdQ_empty) begin
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

	// Signals back to the memory controller
	//assign rd_ready = !macroRdQ_full && !reqQ_full && !macro_req_active && !inbuf_full;	// TODO: double check this
	assign rd_ready = macroRdQ_empty && reqQ_empty && !macro_req_active && tagQ_empty;	// TODO: double check this
	/*
    always@(posedge clk) begin
		if (macro_req_active && reqQ_full) begin
			$display("RD PATH: Unable to inssue another read request! reqQ_full");
		end
		if (macro_req_active && tagQ_full) begin
			$display("RD PATH: Unable to inssue another read request! tagQ_full");
		end
		if (reqQ_enq) begin
			$display("RD PATH: Enqueing read request %d", new_requests_left);
		end
		if (!tagQ_empty) begin
			$display("RD PATH: tagQ has %d entries left, reqQ has %d entries left, respQ has %d entries left, wrValid %d",SoftFIFO_readtagQ.readtagQ.counter,SoftFIFO_reqQ.reqQ.counter,SoftFIFO_respQ.respQ.counter, wrReqValid);
		end
	end
	*/
	// Output responses to the block buffer
	// Arbitrate between the reqQ (read requests) and requests from DNN1AMI_WRPath
	AMIRequest arbWinner;
	logic valid_final_arb;
	
	always_comb begin
		valid_final_arb = 1'b0;
		arbWinner = reqWrPath;
		reqWrPath_grant = 1'b0;
		reqQ_deq        = 1'b0;
		if (wrReqValid) begin
			valid_final_arb = 1'b1;
			arbWinner = reqWrPath;
			if (mem_req_grant) begin
				reqWrPath_grant = 1'b1;
			end
		end else if (reqQ_out.valid && !reqQ_empty) begin
			valid_final_arb = 1'b1;
			arbWinner = reqQ_out;
			if (mem_req_grant) begin
				reqQ_deq = 1'b1;
			end /*else begin
				$display("RD PATH: Won arb but no grant");
			end*/
		end
	end
	
	assign mem_req   = '{valid: (arbWinner.valid && valid_final_arb), isWrite: arbWinner.isWrite, addr: arbWinner.addr  , data: arbWinner.data , size: arbWinner.size};
	/*
	always@(posedge clk) begin
		if (valid_final_arb) begin
			$display("DNN2AMI: A REQUEST IS BEING SENT to the block buffer");
		end
		$display("RDPATH: Read requests left: %d", requests_left);
	end
	*/
	
	
endmodule

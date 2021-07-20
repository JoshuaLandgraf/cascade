import ShellTypes::*;
import AMITypes::*;
import AOSF1Types::*;

`include "dw_params.vh"
`include "common.vh"

module dummy_dnn_ami(
  input  wire                                        clk,
  input  wire                                        reset,
  input  wire                                        start,
  output wire                                        done
);

    reg start_d;
    
    always@(posedge clk) begin
        if (reset) begin
            start_d <= 1'b0;
        end else begin
            if (start) begin
                start_d = 1'b1;
            end
        end
    end

    assign done = start_d;

endmodule

module DNNDrive_SoftReg #(
// ******************************************************************
// Parameters
// ******************************************************************
  parameter integer PU_TID_WIDTH      = 16,
  parameter integer AXI_TID_WIDTH     = 6,
  parameter integer NUM_PU            = `num_pu,
  parameter integer ADDR_W            = 32,
  parameter integer OP_WIDTH          = 16,
  parameter integer AXI_DATA_W        = 64,
  parameter integer NUM_PE            = `num_pe,
  parameter integer BASE_ADDR_W       = ADDR_W,
  parameter integer OFFSET_ADDR_W     = ADDR_W,
  parameter integer TX_SIZE_WIDTH     = 20,
  parameter integer RD_LOOP_W         = 32,
  parameter integer D_TYPE_W          = 2,
  parameter integer ROM_ADDR_W        = 3,
  parameter integer SERDES_COUNT_W    = 6,
  parameter integer PE_SEL_W          = `C_LOG_2(NUM_PE),
  parameter integer DATA_W            = NUM_PE * OP_WIDTH, // double check this
  parameter integer LAYER_PARAM_WIDTH  = 10,
  parameter integer USE_DUMMY          = 0
)
(
    // User clock and reset
    input                               clk,
    input                               rst, 

    input [AMI_APP_BITS-1:0]            srcApp,
    
    // Simplified Memory interface
    output AMIRequest                   mem_reqs        [1:0],
    input                               mem_req_grants  [1:0],
    input AMIResponse                   mem_resps       [1:0],
    output logic                        mem_resp_grants [1:0],

    // PCIe Slot DMA interface
    input PCIEPacket                    pcie_packet_in,
    output                              pcie_full_out,

    output PCIEPacket                   pcie_packet_out,
    input                               pcie_grant_in,

    // Soft register interface
    input SoftRegReq                    softreg_req,
    output SoftRegResp                  softreg_resp
);
    localparam DNNDRIVE_SOFTREG_Type  = 0;
    localparam DNNDRIVE_SOFTREG_Depth = 4;
    
    // DNNWeaver signals
    logic dnn_start;
    wire  dnn_done;
    
    logic dummy_l_inc;
    wire l_inc;
    
    generate
        if  (USE_DUMMY == 1) begin : dummy_dnn_gen
            dummy_dnn_ami
            dummy_inst
            (
                .clk                      ( clk                    ),
                .reset                    ( rst                    ),
                .start                    ( dnn_start              ),
                .done                     ( dnn_done               )
            );
            assign mem_reqs[0] = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0, size: 64};
            assign mem_reqs[1] = '{valid: 0, isWrite: 1'b0, addr: 64'b0, data: 512'b0, size: 64};
            assign mem_resp_grants[0] = 1'b0;
            assign mem_resp_grants[1] = 1'b0;
            assign dummy_l_inc = 1'b0;
            assign l_inc = dummy_l_inc;
        end else begin : real_dnn_gen
          dnnweaver_ami_top #(
          // TODO: Double check all the parameters
          // INPUT PARAMETERS
            .NUM_PE                   ( NUM_PE                   ),
            .NUM_PU                   ( NUM_PU                   ),
            .ADDR_W                   ( ADDR_W                   ),
            .AXI_DATA_W               ( DATA_W                   ),
            .BASE_ADDR_W              ( BASE_ADDR_W              ),
            .OFFSET_ADDR_W            ( OFFSET_ADDR_W            ),
            .RD_LOOP_W                ( RD_LOOP_W                ),
            .TX_SIZE_WIDTH            ( TX_SIZE_WIDTH            ),
            .D_TYPE_W                 ( D_TYPE_W                 ),
            .ROM_ADDR_W               ( ROM_ADDR_W               )
          ) real_accelerator_top ( // PORTS
            .clk                      ( clk                    ),
            .reset                    ( rst                    ),
            .start                    ( dnn_start              ),
            .done                     ( dnn_done               ),

            // Debug signals
            /*
            .dbg_kw (dbg_kw),
            .dbg_kh(dbg_kh),
            .dbg_iw(dbg_iw),
            .dbg_ih(dbg_ih),
            .dbg_ic(dbg_ic),
            .dbg_oc(dbg_oc),
            .buffer_read_count(buffer_read_count),
            .stream_read_count(stream_read_count),
            .inbuf_count(inbuf_count),
            .pu_write_valid(pu_write_valid),
            .wr_cfg_idx(wr_cfg_idx),
            .rd_cfg_idx(rd_cfg_idx),
            .outbuf_push(outbuf_push),
            .pu_controller_state(pu_controller_state),
            .vecgen_state(vecgen_state),
            .vecgen_read_count(vecgen_read_count),        
            */
            // Memory signals
            .flush_buffer (1'b0), // TODO: Actually connect it
            .mem_req(mem_reqs),
            .mem_req_grant(mem_req_grants),
            .mem_resp(mem_resps),
            .mem_resp_grant(mem_resp_grants),
            .l_inc(l_inc)
          );
        end
    endgenerate

    // Dont need the SoftReg interface
    //assign softreg_resp = '{valid: 1'b0, data: 0};
    
	// copied from memdrive
    // clk and debug counter
    wire[63:0] clk_counter;

    // Don't need the PCI-e interface
    assign pcie_full_out = 1'b0;
    assign pcie_packet_out = '{valid: 1'b0, data: 0, slot: 0, pad: 0, last: 1'b0};

    // Response credits
    reg[31:0]   read_resp_credit_cnt;
    logic[31:0] new_read_resp_credit_cnt;
    logic       decr_read_resp_credit_cnt;

    always @(posedge clk) begin 
        if (rst) begin
            read_resp_credit_cnt <= 1'b0;
        end else begin
            read_resp_credit_cnt <= new_read_resp_credit_cnt;
        end
    end   
	
    // Input queue for PCI-e
    wire             sr_inQ_empty;
    wire             sr_inQ_full;
    logic            sr_inQ_enq;
    logic            sr_inQ_deq;
    SoftRegReq       sr_inQ_in;
    SoftRegReq       sr_inQ_out;

    HullFIFO
    #(
        .TYPE                   (DNNDRIVE_SOFTREG_Type),
        .WIDTH                  ($bits(SoftRegReq)),
        .LOG_DEPTH              (DNNDRIVE_SOFTREG_Depth)
    )
    sr_InQ
    (
        .clock                  (clk),
        .reset_n                (~rst),
        .wrreq                  (sr_inQ_enq),
        .data                   (sr_inQ_in),
        .full                   (sr_inQ_full),
        .q                      (sr_inQ_out),
        .empty                  (sr_inQ_empty),
        .rdreq                  (sr_inQ_deq)
    );    

    // Connections to softreg input interface
    assign sr_inQ_in   = softreg_req;
    assign sr_inQ_enq  = softreg_req.valid && (softreg_req.isWrite == 1'b1) && !sr_inQ_full;
    
    logic  incoming_req_is_read;
    assign incoming_req_is_read = softreg_req.valid && (softreg_req.isWrite == 1'b0);
    
    always_comb begin
        new_read_resp_credit_cnt = read_resp_credit_cnt;
        if (incoming_req_is_read && !decr_read_resp_credit_cnt) begin
			$display("Cycle %d DNNDrive %d: Gained response credit", clk_counter, srcApp);
            new_read_resp_credit_cnt = read_resp_credit_cnt + 1;
        end else if (!incoming_req_is_read && decr_read_resp_credit_cnt) begin
			$display("Cycle %d DDNDRive %d: Lost response credit", clk_counter, srcApp);
            new_read_resp_credit_cnt = read_resp_credit_cnt - 1;
        end
        // otherwise either gained/lost none (+0) or both (+0)
    end
    
    // Logic used to program the FSM over PCI-e
    parameter PACKET_COUNT = 8; // 8 64 bit packet contents
    //  Information to read/write
    reg[63:0] program_struct[PACKET_COUNT-1:0];
    logic[63:0] start_addr;
    logic[63:0] total_subs;
    logic[63:0] mask;
    logic[63:0] mode;    
    logic[63:0] start_addr2;
    logic[63:0] addr_delta;
    logic[63:0] canary0;
    logic[63:0] canary1;
    
    reg[3:0] wr_count;
    logic[3:0] new_wr_count;
    logic[($clog2(PACKET_COUNT))-1:0] struct_wr_index;
    logic   struct_wr_en;
    
    assign start_addr  = program_struct[0][63:0];
    assign total_subs  = program_struct[1][63:0];
    assign mask        = program_struct[2][63:0];
    assign mode        = program_struct[3][63:0];
    assign start_addr2 = program_struct[4][63:0];
    assign addr_delta  = program_struct[5][63:0];
    assign canary0     = program_struct[6][63:0];
    assign canary1     = program_struct[7][63:0];
    
    // Counter
    reg[63:0]  start_cycle;
    logic      start_cycle_we;
	reg[63:0]  end_cycle;
	logic      end_cycle_we;
    
    Counter64 
    clk_counter64
    (
        .clk             (clk),
        .rst             (rst),
        .increment       (1'b1), // clock is always incrementing
        .count           (clk_counter)
    );
    
    always@(posedge clk) begin : start_cycle_update
        if (rst) begin
            start_cycle  <= 64'h0;
			end_cycle    <= 64'h0;
        end else begin
            if (start_cycle_we) begin
                start_cycle <= clk_counter;
            end
			if (end_cycle_we) begin
				end_cycle <= clk_counter;
			end
        end
    end
 
    // FSM states
    parameter IDLE        = 4'b0000;
    parameter PROGRAMMING = 4'b0001;
    parameter REQUESTING  = 4'b0010;
    parameter AWAIT_RESP  = 4'b0011;
    parameter CLEAN_UP1   = 4'b0100;
    parameter CLEAN_UP2   = 4'b0101;
    parameter CLEAN_UP3   = 4'b0110;
    parameter CLEAN_UP4   = 4'b0111;
    parameter CLEAN_UP5   = 4'b1000;
    
    // FSM registers
    reg[3:0]   current_state;
    logic[3:0] next_state;

    // FSM reset/update
    always@(posedge clk) begin : fsm_update
        if (rst) begin
            wr_count <=  0;
            current_state  <= IDLE;
        end else begin
            wr_count <= new_wr_count;
            current_state <= next_state;
        end
    end
    // Used when programming the internal struct
    always @(posedge clk) begin : struct_update
        if (struct_wr_en) begin
            program_struct[struct_wr_index] <= sr_inQ_out.data;
        end else begin
            program_struct[struct_wr_index] <= program_struct[struct_wr_index];
        end
    end
    
    // Start logic
    logic intiate_start; 
    reg   start_d;
    assign dnn_start = start_d;
    
    always @(posedge clk) begin : start_update_logic
        if (rst) begin
            start_d <= 1'b0;
        end else begin
            if (intiate_start) begin
                start_d <= 1'b1;
            end else begin
                // always set it to low
                start_d <= 1'b0;
            end
        end
    end

    logic  enough_sr_resp_credits;
    assign enough_sr_resp_credits = (read_resp_credit_cnt != 32'h0000_0000);
	
    // FSM update logic
    always_comb begin
        next_state = current_state;
        struct_wr_en    = 1'b0;
        struct_wr_index = 0;
        sr_inQ_deq    = 1'b0;
        new_wr_count = wr_count;
        softreg_resp = '{valid: 1'b0, data: 0};
        start_cycle_we = 1'b0;
        intiate_start = 1'b0;
     
        decr_read_resp_credit_cnt = 1'b0;
		end_cycle_we = 1'b0;
		
        case (current_state)
            IDLE : begin
                if (!sr_inQ_empty) begin
					$display("Cycle %d DNNDrive %d: Starting programming", clk_counter, srcApp);
                    next_state = PROGRAMMING;
                    //next_state   = CLEAN_UP1;
                end else begin
                    next_state = IDLE;
                end
            end
            PROGRAMMING : begin
                if (!sr_inQ_empty) begin
                    sr_inQ_deq = 1'b1;
                    struct_wr_en = 1'b1;
                    struct_wr_index = wr_count;
                    new_wr_count = wr_count + 1;
                    if (new_wr_count == 4'b1000) begin
                        // Consumed last packet, move on to requesting
                        next_state = REQUESTING;
                        // reset the wr count
                        new_wr_count = 0;
                        // Save the current cycle as the start time stamp
                        start_cycle_we = 1'b1;
                        $display("Cycle %d DNNDrive %d: DONE programming", clk_counter, srcApp);
                    end else begin
                        next_state = PROGRAMMING; // need more packets
                    end
                end else begin
                    // Still need more packet(s) to finish programming
                    next_state = PROGRAMMING;
                end
            end
            REQUESTING : begin
                // Signify start
                intiate_start = 1'b1;
                // Go to await state
                next_state = AWAIT_RESP;
				$display("Cycle %d DNNDrive %d: Starting and transitioning to AWAIT_RESP", clk_counter, srcApp);
            end
            AWAIT_RESP : begin
                // wait for the done signal to be asserted
                //if (dnn_done == 1'b1 || (lhc_enable[0] ? l_inc : 1'b0)) begin
                if (dnn_done == 1'b1) begin
					$display("Cycle %d DNNDrive %d: DNNWeaver DONE", clk_counter, srcApp);
                    next_state = CLEAN_UP1;
					end_cycle_we = 1'b1;
                end else begin
                    next_state = AWAIT_RESP;
                end
            end
            CLEAN_UP1: begin
                if (enough_sr_resp_credits) begin
                    $display("Cycle %d DNNDrive %d: Clean up 1", clk_counter, srcApp);
                    softreg_resp = '{valid: 1'b1, data: start_cycle};
                    decr_read_resp_credit_cnt = 1'b1;
                    next_state = CLEAN_UP2;
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d DNNDrive %d: Staying in Clean up 1, no resp credits (%d)", clk_counter, srcApp, read_resp_credit_cnt);
					end
                    next_state = CLEAN_UP1;
                end
            end
            CLEAN_UP2: begin
                if (enough_sr_resp_credits) begin
                    $display("Cycle %d DNNDrive %d: Clean up 2", clk_counter, srcApp);
                    softreg_resp = '{valid: 1'b1, data: end_cycle};
                    decr_read_resp_credit_cnt = 1'b1;
                    next_state = IDLE;
                    $display("Cycle %d DNNDrive %d: DONE", clk_counter, srcApp);
                end else begin
					if (clk_counter % 100 == 0) begin
						$display("Cycle %d DNNDrive %d: Staying in Clean up 2, no resp credits (%d)", clk_counter, srcApp, read_resp_credit_cnt);
					end
                    next_state = CLEAN_UP2;
                end
            end
            default : begin
                next_state = current_state;
            end
        endcase
    end
    
endmodule

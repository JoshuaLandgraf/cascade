`timescale 1ns/1ps
`include "common.vh"
import ShellTypes::*;
import AMITypes::*;

module mem_controller_top_ami
#( // INPUT PARAMETERS
  parameter integer NUM_PE                            = 4,
  parameter integer NUM_PU                            = 2,
  parameter integer NUM_AXI                           = 1,
  parameter integer OP_WIDTH                          = 16,
  parameter integer AXI_DATA_W                        = 64,
  parameter integer ADDR_W                            = 32,
  parameter integer BASE_ADDR_W                       = ADDR_W,
  parameter integer OFFSET_ADDR_W                     = ADDR_W,
  parameter integer RD_LOOP_W                         = 32,
  parameter integer TX_SIZE_WIDTH                     = 10,
  parameter integer D_TYPE_W                          = 2,
  parameter integer ROM_ADDR_W                        = 2,
  parameter integer ARUSER_W                          = 2,
  parameter integer RUSER_W                           = 2,
  parameter integer BUSER_W                           = 2,
  parameter integer AWUSER_W                          = 2,
  parameter integer WUSER_W                           = 2,
  parameter integer TID_WIDTH                         = 6,
  parameter integer AXI_RD_BUFFER_W                   = 6,
  parameter integer WSTRB_W = AXI_DATA_W/8,
  parameter integer PU_DATA_W = OP_WIDTH * NUM_PE,
  parameter integer STREAM_PU_DATA_W = OP_WIDTH * NUM_PE * NUM_PU,
  parameter integer OUTBUF_DATA_W = PU_DATA_W * NUM_PU,
  parameter integer AXI_OUT_DATA_W = AXI_DATA_W * NUM_PU,
  parameter integer PU_ID_W = $clog2(NUM_PU)+1
)( // PORTS
  input  wire                                         clk,
  input  wire                                         reset,
  input  wire                                         start,
  output wire                                         done,

  // AMI signals
  output AMIRequest                   mem_req        ,
  input                               mem_req_grant  ,
  input  AMIResponse                  mem_resp       ,
  output                              mem_resp_grant ,
 
  output wire  [ RD_LOOP_W            -1 : 0 ]        pu_id_buf,
  output wire  [ D_TYPE_W             -1 : 0 ]        d_type_buf,
  output wire                                         next_read,

  output wire  [ NUM_PU               -1 : 0 ]        outbuf_full,
  input  wire  [ NUM_PU               -1 : 0 ]        outbuf_push,
  input  wire  [ OUTBUF_DATA_W        -1 : 0 ]        outbuf_data_in,

  output wire                                         stream_fifo_empty,
  input  wire                                         stream_fifo_pop,
  output wire  [ PU_DATA_W            -1 : 0 ]        stream_fifo_data_out,

  output wire  [ NUM_PU               -1 : 0 ]        stream_pu_empty,
  input  wire  [ NUM_PU               -1 : 0 ]        stream_pu_pop,
  output wire  [ STREAM_PU_DATA_W     -1 : 0 ]        stream_pu_data_out,

  output wire                                         buffer_read_last,
  output wire                                         buffer_read_empty,
  input  wire                                         buffer_read_req,
  output wire  [ PU_ID_W              -1 : 0 ]        buffer_pu_id,
  output wire  [ AXI_DATA_W           -1 : 0 ]        buffer_read_data_out,

  // Debug
  output reg  [ 32                   -1 : 0 ]         buffer_read_count,
  output reg  [ 32                   -1 : 0 ]         stream_read_count,
  output wire  [ 11                   -1 : 0 ]        inbuf_count,
  output wire  [ NUM_PU               -1 : 0 ]        pu_write_valid,
  output wire  [ ROM_ADDR_W           -1 : 0 ]        wr_cfg_idx,
  output wire  [ ROM_ADDR_W           -1 : 0 ]        rd_cfg_idx

);

// ******************************************************************
// LOCALPARAMS
// ******************************************************************

// ******************************************************************
// WIRES
// ******************************************************************
  reg  [ 32                   -1 : 0 ]        inbuf_push_count;
  wire [ AXI_OUT_DATA_W       -1 : 0 ]        outbuf_data_out;
  wire [ AXI_DATA_W           -1 : 0 ]        inbuf_data_in;

  wire                                        read_full;
  // Memory Controller Interface
  wire                                        rd_req;
  wire                                        rd_ready;
  wire                                        axi_rd_ready;
  wire [ TX_SIZE_WIDTH        -1 : 0 ]        rd_req_size;
  wire [ TX_SIZE_WIDTH        -1 : 0 ]        rd_rvalid_size;
  wire [ ADDR_W               -1 : 0 ]        rd_addr;

  //wire [ RD_LOOP_W            -1 : 0 ]        buffer_pu_id;
  wire [ D_TYPE_W             -1 : 0 ]        d_type;

  wire                                        wr_req;
  wire [PU_ID_W-1:0] wr_pu_id;
  wire [PU_ID_W-1:0] pu_id;
  wire                                        wr_ready;
  wire [ ADDR_W               -1 : 0 ]        wr_addr;
  wire [ TX_SIZE_WIDTH        -1 : 0 ]        wr_req_size;
  wire                                        wr_done;

  wire [ NUM_PU               -1 : 0 ]        outbuf_empty;
  wire [ NUM_PU               -1 : 0 ]        write_valid;
  wire [ NUM_PU               -1 : 0 ]        outbuf_pop;

  assign M_AXI_AWUSER = 0;
  assign M_AXI_WUSER = 0;
  assign M_AXI_ARUSER = 0;

  wire axi_rd_buffer_push;
  wire axi_rd_buffer_pop;
  wire axi_rd_buffer_empty;
  wire axi_rd_buffer_full;
  wire [AXI_DATA_W-1:0] axi_rd_buffer_data_in;
  wire [AXI_DATA_W-1:0] axi_rd_buffer_data_out;
  reg  [AXI_DATA_W-1:0] axi_rd_buffer_data_out_d;

  localparam STREAM_FIFO_ADDR_W = 8;

  wire stream_fifo_push;
  //wire stream_fifo_pop;
  //wire stream_fifo_empty;
  wire stream_fifo_full;
  wire [STREAM_FIFO_ADDR_W:0] stream_fifo_count;
  wire [STREAM_FIFO_ADDR_W:0] stream_fifo_count_almost_max;
  wire [PU_DATA_W-1:0] stream_fifo_data_in;
  //wire [AXI_DATA_W-1:0] stream_fifo_data_out;

  wire stream_push;
  wire buffer_push;
  wire stream_full;
  wire buffer_full;
  wire [AXI_DATA_W-1:0] stream_data_in;

  localparam BUFFER_READ_ADDR_W = 8; // WAS 10  TODO: DOUBLE CHECK

  wire buffer_read_push;
  wire buffer_read_pop;
  //wire buffer_read_empty;
  wire buffer_read_full;
  wire [AXI_DATA_W-1:0] buffer_read_data_in;
  wire [BUFFER_READ_ADDR_W:0] buf_rd_fifo_count;
  wire [BUFFER_READ_ADDR_W:0] buffer_read_count_almost_max;
  //wire [AXI_DATA_W-1:0] buffer_read_data_out;

// ==================================================================
// ==================================================================
  mem_controller #(
  // INPUT PARAMETERS
    .NUM_PE                   ( NUM_PE                   ),
    .NUM_PU                   ( NUM_PU                   ),
    .ADDR_W                   ( ADDR_W                   ),
    .BASE_ADDR_W              ( BASE_ADDR_W              ),
    .OFFSET_ADDR_W            ( OFFSET_ADDR_W            ),
    .RD_LOOP_W                ( RD_LOOP_W                ),
    .TX_SIZE_WIDTH            ( TX_SIZE_WIDTH            ),
    .D_TYPE_W                 ( D_TYPE_W                 )
  ) u_mem_ctrl ( // PORTS
    .clk                      ( clk                      ),
    .reset                    ( reset                    ),
    .start                    ( start                    ),
    .done                     ( done                     ),
    .rd_cfg_idx               ( rd_cfg_idx               ),
    .wr_cfg_idx               ( wr_cfg_idx               ),
    .pu_id                    ( pu_id                    ),
    .d_type                   ( d_type                   ),
    .rd_req                   ( rd_req                   ),
    .rd_ready                 ( rd_ready                 ),
    .rd_req_size              ( rd_req_size              ),
    .rd_rvalid_size           ( rd_rvalid_size           ),
    .rd_addr                  ( rd_addr                  ),
    .wr_req                   ( wr_req                   ),
    .wr_pu_id                 ( wr_pu_id                 ),
    .wr_ready                 ( wr_ready                 ),
    .wr_req_size              ( wr_req_size              ),
    .wr_addr                  ( wr_addr                  ),
    .wr_done                  ( wr_done                  )
  );
 
// ==================================================================

// ==================================================================
  dnn2ami_wrapper
  #(
    .AXI_DATA_W               ( AXI_DATA_W               ),
    .ADDR_W                   ( ADDR_W                   ),
    .TX_SIZE_WIDTH            ( TX_SIZE_WIDTH            ),
    .NUM_AXI                  ( NUM_AXI                  ),
    .NUM_PU                   ( NUM_PU                   )
  )
  u_axim
  (
    .clk                      ( clk                      ),
    .reset                    ( reset                    ),

    .mem_req                  (mem_req                   ),
    .mem_req_grant            (mem_req_grant             ),
    .mem_resp                 (mem_resp                  ),
    .mem_resp_grant           (mem_resp_grant            ),

    .outbuf_empty             ( outbuf_empty             ),
    .outbuf_pop               ( outbuf_pop               ),
    .data_from_outbuf         ( outbuf_data_out          ),

    .data_to_inbuf            ( axi_rd_buffer_data_in    ),
    .inbuf_push               ( axi_rd_buffer_push       ),
    .inbuf_full               ( read_full                ),

    .rd_req                   ( rd_req                   ),
    .rd_ready                 ( axi_rd_ready             ),
    .rd_req_size              ( rd_req_size              ),
    .rd_addr                  ( rd_addr                  ),

    .wr_req                   ( wr_req                   ),
    .wr_pu_id                 ( wr_pu_id                 ),
    .wr_done                  ( wr_done                  ),
    .wr_ready                 ( wr_ready                 ),
    .wr_req_size              ( wr_req_size              ),
    .wr_addr                  ( wr_addr                  ),
    .write_valid              ( write_valid              )
  );
// ==================================================================
wire read_info_full;
wire buffer_counter_full;

assign read_full = axi_rd_buffer_full || read_info_full || buffer_counter_full;

assign rd_ready = !buffer_counter_full && axi_rd_ready;


// ==================================================================
// Stream PU Buffer
// ==================================================================

  localparam STREAM_PU_FIFO_ADDR_W = 6;
  reg stream_pu_full;
  wire [STREAM_PU_FIFO_ADDR_W-1:0] stream_pu_count;
  wire stream_pu_push;
  wire [PU_ID_W-1:0] stream_pu_id;

assign stream_pu_count = STREAM_PU_GEN[NUM_PU-1].stream_pu_fifo_count;

always @(posedge clk)
  if (reset)
    stream_pu_full <= 1'b0;
  else
    stream_pu_full <= stream_pu_count > (1<<STREAM_PU_FIFO_ADDR_W) - 4;

genvar i;
generate
  for (i=0; i<NUM_PU; i=i+1)
  begin: STREAM_PU_GEN

    `ifdef simulation
      integer push_count = 0;
      integer packer_push_count = 0;
      always @(posedge clk)
      begin
        if (reset) begin
          push_count <= 0;
          packer_push_count <= 0;
        end else begin
          push_count <= push_count + stream_pu_push_local;
          packer_push_count <= packer_push_count + stream_pu_fifo_push;
        end
      end
    `endif

    wire stream_pu_push_local;
    assign stream_pu_push_local = stream_pu_push && stream_pu_id == i;

    wire [AXI_DATA_W-1:0] stream_pu_data_in;

    wire [ PU_DATA_W               -1 : 0 ]     stream_pu_fifo_data_in;
    wire [ PU_DATA_W               -1 : 0 ]     stream_pu_fifo_data_out;
    wire                                        stream_pu_fifo_push;
    wire                                        stream_pu_fifo_pop;
    wire                                        stream_pu_fifo_full;
    wire                                        stream_pu_fifo_empty;
    wire [STREAM_PU_FIFO_ADDR_W:0] stream_pu_fifo_count; // TODO big change

    assign stream_pu_data_in = axi_rd_buffer_data_out_d;

    assign stream_pu_fifo_pop = stream_pu_pop[i];
    assign stream_pu_empty[i] = stream_pu_fifo_empty;
    assign stream_pu_data_out[i*PU_DATA_W+:PU_DATA_W] = stream_pu_fifo_data_out;

    data_packer #(
      .IN_WIDTH                 ( AXI_DATA_W               ),
      .OUT_WIDTH                ( PU_DATA_W                )
    ) packer (
      .clk                      ( clk                      ),  //input
      .reset                    ( reset                    ),  //input
      .s_write_req              ( stream_pu_push_local     ),  //input
      .s_write_data             ( stream_pu_data_in        ),  //input
      .s_write_ready            (                          ),  //output
      .m_write_req              ( stream_pu_fifo_push      ),  //output
      .m_write_data             ( stream_pu_fifo_data_in   ),  //output
      .m_write_ready            ( !stream_pu_full          )   //input
      );

    fifo #(
      .DATA_WIDTH               ( PU_DATA_W                ),
      .ADDR_WIDTH               ( STREAM_PU_FIFO_ADDR_W    )
    ) stream_pu (
      .clk                      ( clk                      ),  //input
      .reset                    ( reset                    ),  //input
      .push                     ( stream_pu_fifo_push      ),  //input
      .pop                      ( stream_pu_fifo_pop       ),  //input
      .data_in                  ( stream_pu_fifo_data_in   ),  //input
      .data_out                 ( stream_pu_fifo_data_out  ),  //output
      .full                     ( stream_pu_fifo_full      ),  //output
      .empty                    ( stream_pu_fifo_empty     ),  //output
      .fifo_count               ( stream_pu_fifo_count     )   //output
    );

  end
endgenerate

// ==================================================================


// ==================================================================
// OutBuf - Output Buffer
// ==================================================================
	
generate
  for (i=0; i<NUM_PU; i=i+1)
  begin: OUTPUT_BUFFER_GEN

    wire [ PU_DATA_W               -1 : 0 ]     ob_iw_data_in;
    wire [ PU_DATA_W               -1 : 0 ]     ob_iw_data_out;
    wire                                        ob_iw_push;
    wire                                        ob_iw_pop;
    wire                                        ob_iw_full;
    wire                                        ob_iw_empty;

    assign outbuf_full[i] = ob_iw_full;
    assign ob_iw_push = outbuf_push[i];
    assign ob_iw_data_in = outbuf_data_in[i*PU_DATA_W+:PU_DATA_W];

    fifo #(
      .DATA_WIDTH               ( PU_DATA_W                ),
      .ADDR_WIDTH               ( 7                        )
    ) outbuf_iwidth (
      .clk                      ( clk                      ),  //input
      .reset                    ( reset                    ),  //input
      .push                     ( ob_iw_push               ),  //input
      .pop                      ( ob_iw_pop                ),  //input
      .data_in                  ( ob_iw_data_in            ),  //input
      .data_out                 ( ob_iw_data_out           ),  //output
      .full                     ( ob_iw_full               ),  //output
      .empty                    ( ob_iw_empty              ),  //output
      .fifo_count               (    )   //output
      );

    wire m_packed_read_req;
    wire m_packed_read_ready;
    wire [PU_DATA_W-1:0] m_packed_read_data;
    wire m_unpacked_write_req;
    wire m_unpacked_write_ready;
    wire [AXI_DATA_W-1:0] m_unpacked_write_data;

    assign m_packed_read_ready = !ob_iw_empty;
    assign ob_iw_pop = m_packed_read_req;
    assign m_packed_read_data = ob_iw_data_out;

    data_unpacker #(
      .IN_WIDTH                 ( PU_DATA_W                ),
      .OUT_WIDTH                ( AXI_DATA_W               )
    ) d_unpacker (
      .clk                      ( clk                      ),  //input
      .reset                    ( reset                    ),  //input
      .m_packed_read_req        ( m_packed_read_req        ),  //output
      .m_packed_read_ready      ( m_packed_read_ready      ),  //input
      .m_packed_read_data       ( m_packed_read_data       ),  //output
      .m_unpacked_write_req     ( m_unpacked_write_req     ),  //output
      .m_unpacked_write_ready   ( m_unpacked_write_ready   ),  //input
      .m_unpacked_write_data    ( m_unpacked_write_data    )   //output
      );

    wire [ AXI_DATA_W               -1 : 0 ]    ob_ow_data_in;
    wire [ AXI_DATA_W               -1 : 0 ]    ob_ow_data_out;
    wire                                        ob_ow_push;
    wire                                        ob_ow_pop;
    wire                                        ob_ow_full;
    wire                                        ob_ow_empty;

    assign outbuf_empty[i] = ob_ow_empty;
    assign ob_ow_pop = outbuf_pop[i];
    assign outbuf_data_out[i*AXI_DATA_W+:AXI_DATA_W] = ob_ow_data_out;

    assign ob_ow_push = m_unpacked_write_req;
    assign m_unpacked_write_ready = !ob_ow_full;
    assign ob_ow_data_in = m_unpacked_write_data;

    assign write_valid[i] = ob_ow_push;

    reg  [ 32                   -1 : 0 ]        obuf_ow_push_count;
    always @(posedge clk)
      if (reset)
        obuf_ow_push_count <= 0;
      else if (ob_ow_push)
        obuf_ow_push_count <= obuf_ow_push_count + 1;


    fifo_fwft #(
      .DATA_WIDTH               ( AXI_DATA_W               ),
      .ADDR_WIDTH               ( 5                        )
    ) outbuf_owidth (
      .clk                      ( clk                      ),  //input
      .reset                    ( reset                    ),  //input
      .push                     ( ob_ow_push               ),  //input
      .pop                      ( ob_ow_pop                ),  //input
      .data_in                  ( ob_ow_data_in            ),  //input
      .data_out                 ( ob_ow_data_out           ),  //output
      .full                     ( ob_ow_full               ),  //output
      .empty                    ( ob_ow_empty              ),  //output
      .fifo_count               (                          )   //output
      );
  end
endgenerate

// ==================================================================

// ==================================================================
// InBuf - Input Buffer
// ==================================================================

  fifo#(
    .DATA_WIDTH               ( AXI_DATA_W               ),
    .ADDR_WIDTH               ( AXI_RD_BUFFER_W          )
  ) axi_rd_buffer (
    .clk                      ( clk                      ),  //input
    .reset                    ( reset                    ),  //input
    .push                     ( axi_rd_buffer_push       ),  //input
    .full                     ( axi_rd_buffer_full       ),  //output
    .data_in                  ( axi_rd_buffer_data_in    ),  //input
    .pop                      ( axi_rd_buffer_pop        ),  //input
    .empty                    ( axi_rd_buffer_empty      ),  //output
    .data_out                 ( axi_rd_buffer_data_out   ),  //output
    .fifo_count               (                          )   //output
  );

  assign stream_data_in = axi_rd_buffer_data_out_d;

  data_packer #(
    .IN_WIDTH                 ( AXI_DATA_W               ),
    .OUT_WIDTH                ( PU_DATA_W                )
  ) packer (
    .clk                      ( clk                      ),  //input
    .reset                    ( reset                    ),  //input
    .s_write_req              ( stream_push              ),  //input
    .s_write_data             ( stream_data_in           ),  //input
    .s_write_ready            (                          ),  //output
    .m_write_req              ( stream_fifo_push         ),  //output
    .m_write_data             ( stream_fifo_data_in      ),  //output
    .m_write_ready            ( !stream_fifo_full        )   //input
  );

  reg stream_fifo_almost_full;
  assign stream_full = stream_fifo_almost_full;

  assign stream_fifo_count_almost_max = (1<<STREAM_FIFO_ADDR_W) - 16;

  always @(posedge clk)
  begin: STREAM_FIFO_ALMOST_FULL
    if (reset)
      stream_fifo_almost_full <= 1'b0;
    else
      stream_fifo_almost_full <= stream_fifo_count >= stream_fifo_count_almost_max;
  end

  fifo#(
    .DATA_WIDTH               ( PU_DATA_W                ),
    .ADDR_WIDTH               ( STREAM_FIFO_ADDR_W       )
  ) stream_fifo (
    .clk                      ( clk                      ),  //input
    .reset                    ( reset                    ),  //input
    .push                     ( stream_fifo_push         ),  //input
    .full                     ( stream_fifo_full         ),  //output
    .data_in                  ( stream_fifo_data_in      ),  //input
    .pop                      ( stream_fifo_pop          ),  //input
    .empty                    ( stream_fifo_empty        ),  //output
    .data_out                 ( stream_fifo_data_out     ),  //output
    .fifo_count               ( stream_fifo_count        )   //output
  );

  assign buffer_read_data_in = axi_rd_buffer_data_out_d;
  assign buffer_read_push = buffer_push;

  /*
  always @(posedge clk) begin
	if (buffer_read_pop) begin 
		$display("MCT: Popping read buffer");
	end
	if (buffer_read_push) begin
		$display("MCT: Pushing read buffer");
	end
  end
  */
  
  reg buffer_read_almost_full;
  assign buffer_full = buffer_read_almost_full;

  assign buffer_read_count_almost_max = (1<<BUFFER_READ_ADDR_W) - 16;
  always @(posedge clk)
  begin: BUFFER_READ_ALMOST_FULL
    if (reset)
      buffer_read_almost_full <= 1'b0;
    else
      buffer_read_almost_full <= buf_rd_fifo_count >= buffer_read_count_almost_max;
  end

  fifo#(
    .DATA_WIDTH               ( AXI_DATA_W               ),
    .ADDR_WIDTH               ( BUFFER_READ_ADDR_W       )
  ) buffer_read (
    .clk                      ( clk                      ),  //input
    .reset                    ( reset                    ),  //input
    .push                     ( buffer_read_push         ),  //input
    .full                     ( buffer_read_full         ),  //output
    .data_in                  ( buffer_read_data_in      ),  //input
    .pop                      ( buffer_read_pop          ),  //input
    .empty                    ( buffer_read_empty        ),  //output
    .data_out                 ( buffer_read_data_out     ),  //output
    .fifo_count               ( buf_rd_fifo_count        )   //output
  );

  buffer_read_counter #(
    .NUM_PU                   ( NUM_PU                   ),
    .D_TYPE_W                 ( D_TYPE_W                 ),
    .RD_SIZE_W                ( TX_SIZE_WIDTH            )
  )
  u_buffer_counter
  (
    .clk                      ( clk                      ),
    .reset                    ( reset                    ),
    .read_info_full           ( buffer_counter_full      ),
    .buffer_read_req          ( buffer_read_req          ),
    .buffer_read_last         ( buffer_read_last         ),
    .buffer_read_pop          ( buffer_read_pop          ),
    .buffer_read_empty        ( buffer_read_empty        ),
    .pu_id                    ( pu_id_buf                ),
    .rd_req                   ( rd_req                   ),
    .rd_req_size              ( rd_req_size              ),
    .rd_req_pu_id             ( pu_id                    ),
    .rd_req_d_type            ( d_type                   )
  );

  always @(posedge clk)
    if (reset)
      inbuf_push_count <= 0;
    else if (stream_push || buffer_push)
      inbuf_push_count <= inbuf_push_count + 1;
// ==================================================================

// ==================================================================
// PU_ID & D_TYPE
// ==================================================================
reg inbuf_valid_read;
  always @(posedge clk)
    if (reset)
      inbuf_valid_read <= 0;
    else
      inbuf_valid_read <= (stream_fifo_pop && !stream_fifo_empty) ||
    (buffer_read_pop && !buffer_read_empty);

  reg  [ D_TYPE_W             -1 : 0 ]        d_type_buf_d;
  always @(posedge clk)
    if (reset)
      d_type_buf_d <= 0;
    else
      d_type_buf_d <=  d_type_buf;

  always @(posedge clk)
    if (reset)
      buffer_read_count <= 0;
    else if (buffer_read_pop && !buffer_read_empty)
      buffer_read_count <=  buffer_read_count + 1'b1;

  reg [32-1:0] buffer_write_count;
  reg [32-1:0] buffer_push_count;
  always @(posedge clk)
    if (reset)
      buffer_write_count <= 0;
    else if (buffer_read_push && !buffer_read_full)
      buffer_write_count <= buffer_write_count + 1'b1;
  always @(posedge clk)
    if (reset)
      buffer_push_count <= 0;
    else if (buffer_read_push && !buffer_read_full)
      buffer_push_count <= buffer_push_count + 1'b1;

  reg  [ 32                   -1 : 0 ]         stream_packer_push_count;
  always @(posedge clk)
    if (reset)
      stream_read_count <= 0;
    else if (stream_fifo_pop && !stream_fifo_empty)
      stream_read_count <=  stream_read_count + 1'b1;

  always @(posedge clk)
    if (reset)
      stream_packer_push_count <= 0;
    else if (stream_push)
      stream_packer_push_count <=  stream_packer_push_count + 1'b1;

read_info #(
  .NUM_PU                   ( NUM_PU                   ),
  .D_TYPE_W                 ( D_TYPE_W                 ),
  .RD_SIZE_W                ( TX_SIZE_WIDTH            )
)
u_read_info
(
  .clk                      ( clk                      ),
  .reset                    ( reset                    ),
  .inbuf_pop                ( axi_rd_buffer_pop        ),
  .inbuf_empty              ( axi_rd_buffer_empty      ),
  .read_info_full           ( read_info_full           ),
  .rd_req                   ( rd_req                   ),
  .rd_req_size              ( rd_req_size              ),
  .rd_req_pu_id             ( pu_id                    ),
  .rd_req_d_type            ( d_type                   ),
  .pu_id                    (                          ),
  .stream_pu_push           ( stream_pu_push           ),
  .stream_pu_id             ( stream_pu_id             ),
  .stream_push              ( stream_push              ),
  .buffer_push              ( buffer_push              ),
  .stream_full              ( stream_full              ),
  .stream_pu_full           ( stream_pu_full           ),
  .buffer_full              ( buffer_full              ),
  .d_type                   ( d_type_buf               )
  );

always @(posedge clk)
begin
  if (reset)
    axi_rd_buffer_data_out_d <= 0;
  else
    axi_rd_buffer_data_out_d <= axi_rd_buffer_data_out;
end


// ==================================================================

// ==================================================================
// DEBUG
// ==================================================================
  assign pu_write_valid = write_valid;
// ==================================================================
endmodule

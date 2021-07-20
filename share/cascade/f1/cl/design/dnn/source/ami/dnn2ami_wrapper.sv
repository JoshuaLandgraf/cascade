`timescale 1ns/1ps
`include "common.vh"
import ShellTypes::*;
import AMITypes::*;
module dnn2ami_wrapper
#( // INPUT PARAMETERS
  parameter integer NUM_PE                            = 4,
  parameter integer NUM_PU                            = 2,
  parameter integer OP_WIDTH                          = 16,
  parameter integer AXI_DATA_W                        = 64,
  parameter integer ADDR_W                            = 32,
  parameter integer BASE_ADDR_W                       = ADDR_W,
  parameter integer OFFSET_ADDR_W                     = ADDR_W,
  parameter integer RD_LOOP_W                         = 32,
  parameter integer TX_SIZE_WIDTH                     = 10,
  parameter integer D_TYPE_W                          = 2,
  parameter integer ROM_ADDR_W                        = 2,
  parameter integer TID_WIDTH                         = 6,
  parameter integer AXI_RD_BUFFER_W                   = 6,
  parameter integer NUM_AXI                           = 1,
  parameter integer WSTRB_W = AXI_DATA_W/8,
  parameter integer PU_DATA_W = OP_WIDTH * NUM_PE,
  parameter integer OUTBUF_DATA_W = PU_DATA_W * NUM_PU,
  parameter integer AXI_OUT_DATA_W = AXI_DATA_W * NUM_PU,
  parameter integer PU_ID_W = `C_LOG_2(NUM_PU)+1
)( // PORTS
  input  wire                                         clk,
  input  wire                                         reset,

    // AMI signals
  output AMIRequest                   mem_req        ,
  input                               mem_req_grant  ,
  input  AMIResponse                  mem_resp       ,
  output                              mem_resp_grant ,

  input  wire  [ NUM_PU               -1 : 0 ]        outbuf_empty,
  output wire  [ NUM_PU               -1 : 0 ]        outbuf_pop,
  input  wire  [ OUTBUF_DATA_W        -1 : 0 ]        data_from_outbuf,
  input  wire  [ NUM_PU               -1 : 0 ]        write_valid,

  input  wire                                         inbuf_full,
  output wire                                         inbuf_push,
  output wire  [ AXI_DATA_W           -1 : 0 ]        data_to_inbuf,

    // Memory Controller Interface - Read
  input  wire                                         rd_req,
  output wire                                         rd_ready,
  input  wire  [ TX_SIZE_WIDTH        -1 : 0 ]        rd_req_size,
  input  wire  [ ADDR_W               -1 : 0 ]        rd_addr,

    // Memory Controller Interface - Write
  input  wire                                         wr_req,
  input  wire  [ PU_ID_W              -1 : 0 ]        wr_pu_id,
  output wire                                         wr_ready,
  input  wire  [ TX_SIZE_WIDTH        -1 : 0 ]        wr_req_size,
  input  wire  [ ADDR_W               -1 : 0 ]        wr_addr,
  output wire                                         wr_done
);
// ******************************************************************
// LOCALPARAMS
// ******************************************************************

// ******************************************************************
// WIRES
// ******************************************************************

/*localparam integer PU_PER_AXI = ceil_a_by_b(NUM_PU, NUM_AXI);
localparam integer AXI_ID_W = `C_LOG_2(NUM_AXI+0);
localparam integer AXI_PU_ID_W = `C_LOG_2(PU_PER_AXI);
*/

DNN2AMI
#(
    .NUM_PU                   ( NUM_PU                   ),
    .AXI_ID                   ( 0                        ),
    .TID_WIDTH                ( TID_WIDTH                ),
    .AXI_DATA_WIDTH           ( AXI_DATA_W               ),
    .TX_SIZE_WIDTH            ( TX_SIZE_WIDTH            )
) u_axim (
    .clk                      ( clk                      ),
    .rst                      ( reset                    ),
    .mem_req                  ( mem_req                  ),
    .mem_req_grant            ( mem_req_grant            ),
    .mem_resp                 ( mem_resp                 ),
    .mem_resp_grant           ( mem_resp_grant           ),
    .outbuf_empty             ( outbuf_empty             ), // TODO: ????
    .outbuf_pop               ( outbuf_pop               ),
    .data_from_outbuf         ( data_from_outbuf     	 ),
    .data_to_inbuf            ( data_to_inbuf            ),
    .inbuf_push               ( inbuf_push               ),
    .inbuf_full               ( inbuf_full               ),
    .wr_req                   ( wr_req                   ),
    .wr_addr                  ( wr_addr                  ),
    .wr_pu_id                 ( wr_pu_id                 ),
    .wr_ready                 ( wr_ready                 ),
    .wr_done                  ( wr_done                  ), // double check
    .wr_req_size              ( wr_req_size              ),
    .write_valid              ( write_valid              ),
    .rd_req                   ( rd_req                   ),
    .rd_ready                 ( rd_ready                 ),
    .rd_req_size              ( rd_req_size              ),
    .rd_addr                  ( rd_addr                  )
);
// ******************************************************************

endmodule

/////////////////////////////////////////////////////////////////////
////                                                             ////
////  FPU                                                        ////
////  Floating Point Unit (Double precision)                     ////
////                                                             ////
////  Author: David Lundgren                                     ////
////          davidklun@gmail.com                                ////
////                                                             ////
/////////////////////////////////////////////////////////////////////
////                                                             ////
//// Copyright (C) 2009 David Lundgren                           ////
////                  davidklun@gmail.com                        ////
////                                                             ////
//// This source file may be used and distributed without        ////
//// restriction provided that this copyright statement is not   ////
//// removed from the file and that any derivative work contains ////
//// the original copyright notice and the associated disclaimer.////
////                                                             ////
////     THIS SOFTWARE IS PROVIDED ``AS IS'' AND WITHOUT ANY     ////
//// EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED   ////
//// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS   ////
//// FOR A PARTICULAR PURPOSE. IN NO EVENT SHALL THE AUTHOR      ////
//// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,         ////
//// INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES    ////
//// (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE   ////
//// GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR        ////
//// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF  ////
//// LIABILITY, WHETHER IN  CONTRACT, STRICT LIABILITY, OR TORT  ////
//// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT  ////
//// OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE         ////
//// POSSIBILITY OF SUCH DAMAGE.                                 ////
////                                                             ////
/////////////////////////////////////////////////////////////////////

// Refactored April 2019 for Cascade compatibility by Tiffany Yang

module fpu_round( 
                  clk, 
                  rst, 
                  enable, 
                  round_mode, 
                  sign_term, 
                  mantissa_term, 
                  exponent_term, 
                  round_out, 
                  exponent_final
                  );

  input wire clk;
  input wire rst;
  input wire enable;
  input wire [1:0] round_mode;
  input wire sign_term;
  input wire [55:0] mantissa_term;
  input wire [11:0] exponent_term;
  output reg [63:0] round_out;
  output reg [11:0] exponent_final;

  wire [55:0] rounding_amount;
  wire round_nearest;
  wire round_to_zero;
  wire round_to_pos_inf;
  wire round_to_neg_inf;
  wire round_nearest_trigger;
  wire round_to_pos_inf_trigger;
  wire round_to_neg_inf_trigger;
  wire round_trigger;


  reg [55:0] sum_round;
  wire sum_round_overflow = sum_round[55]; 
  // will be 0 if no carry, 1 if overflow from the rounding unit
  // overflow from rounding is extremely rare, but possible
  reg [55:0] sum_round_2;
  reg [11:0] exponent_round;
  reg [55:0] sum_final; 

  assign rounding_amount = { 53'b0, 1'b1, 2'b0};
  assign round_nearest = (round_mode == 2'b00);
  assign round_to_zero = (round_mode == 2'b01);
  assign round_to_pos_inf = (round_mode == 2'b10);
  assign round_to_neg_inf = (round_mode == 2'b11);
  assign round_nearest_trigger = round_nearest &  mantissa_term[1]; 
  assign round_to_pos_inf_trigger = !sign_term & |mantissa_term[1:0]; 
  assign round_to_neg_inf_trigger = sign_term & |mantissa_term[1:0];
  assign round_trigger = ( round_nearest & round_nearest_trigger)
         | (round_to_pos_inf & round_to_pos_inf_trigger) 
         | (round_to_neg_inf & round_to_neg_inf_trigger);


  always @(posedge clk) begin
    if (rst) begin
      sum_round <= 0;
      sum_round_2 <= 0;
      exponent_round <= 0;
      sum_final <= 0; 
      exponent_final <= 0;
      round_out <= 0;
    end
    else begin
      sum_round <= rounding_amount + mantissa_term;
      sum_round_2 <= sum_round_overflow ? sum_round >> 1 : sum_round;
      exponent_round <= sum_round_overflow ? (exponent_term + 1) : exponent_term;
      sum_final <= round_trigger ? sum_round_2 : mantissa_term; 
      exponent_final <= round_trigger ? exponent_round : exponent_term;
      round_out <= { sign_term, exponent_final[10:0], sum_final[53:2] };
    end
  end
endmodule  

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

module fpu_sub( 
                clk, 
                rst, 
                enable, 
                opa, 
                opb, 
                fpu_op, 
                sign, 
                diff_2, 
                exponent_2
                );

  parameter WIDTH = 56;
  parameter WIDTH_LOG = 6;

  input wire clk;
  input wire rst;
  input wire enable;
  input wire [63:0] opa, opb;    
  input wire [2:0] fpu_op;
  output reg sign;
  output reg [55:0] diff_2;
  output reg [10:0] exponent_2;
  
  reg [6:0]   diff_shift;
  reg [6:0]   diff_shift_2;

  reg   [10:0] exponent_a;
  reg   [10:0] exponent_b;
  reg   [51:0] mantissa_a;
  reg   [51:0] mantissa_b;
  reg   expa_gt_expb;
  reg   expa_et_expb;
  reg   mana_gtet_manb;
  reg   a_gtet_b;
  reg   [10:0] exponent_small;
  reg   [10:0] exponent_large;
  reg   [51:0] mantissa_small;
  reg   [51:0] mantissa_large;
  reg   small_is_denorm;
  reg   large_is_denorm;
  reg   large_norm_small_denorm;
  reg   small_is_nonzero;
  reg   [10:0] exponent_diff;
  reg   [54:0] minuend;
  reg   [54:0] subtrahend;
  reg   [54:0] subtra_shift;
  wire   subtra_shift_nonzero = |subtra_shift[54:0];
  wire   subtra_fraction_enable = small_is_nonzero & !subtra_shift_nonzero;
  wire   [54:0] subtra_shift_2 = { 54'b0, 1'b1 };
  reg   [54:0] subtra_shift_3;
  reg   [54:0] diff;
  reg   diffshift_gt_exponent;
  reg   diffshift_et_55; // when the difference = 0
  reg   [54:0] diff_1;
  reg   [10:0] exponent;

  wire [WIDTH_LOG - 1:0] msb;
  
  wire   in_norm_out_denorm = (exponent_large > 0) & (exponent== 0);


  always @(posedge clk) begin
    if (rst) begin
      exponent_a <= 0;
      exponent_b <= 0;
      mantissa_a <= 0;
      mantissa_b <= 0;
      expa_gt_expb <= 0;
      expa_et_expb <= 0;
      mana_gtet_manb <= 0;
      a_gtet_b <= 0;
      sign <= 0;
      exponent_small  <= 0;
      exponent_large  <= 0;
      mantissa_small  <= 0;
      mantissa_large  <= 0;
      small_is_denorm <= 0;
      large_is_denorm <= 0;
      large_norm_small_denorm <= 0;
      small_is_nonzero <= 0;
      exponent_diff <= 0;
      minuend <= 0;
      subtrahend <= 0;
      subtra_shift <= 0;
      subtra_shift_3 <= 0;
      diff_shift_2 <= 0;
      diff <= 0;
      diffshift_gt_exponent <= 0;
      diffshift_et_55 <= 0;
      diff_1 <= 0;
      exponent <= 0;
      exponent_2 <= 0;
      diff_2 <= 0;
    end
    else if (enable) begin
      exponent_a <= opa[62:52];
      exponent_b <= opb[62:52];
      mantissa_a <= opa[51:0];
      mantissa_b <= opb[51:0];
      expa_gt_expb <= exponent_a > exponent_b;
      expa_et_expb <= exponent_a == exponent_b;
      mana_gtet_manb <= mantissa_a >= mantissa_b;
      a_gtet_b <= expa_gt_expb | (expa_et_expb & mana_gtet_manb);
      sign <= a_gtet_b ? opa[63] :!opb[63] ^ (fpu_op == 3'b000);
      exponent_small  <= a_gtet_b ? exponent_b : exponent_a;
      exponent_large  <= a_gtet_b ? exponent_a : exponent_b;
      mantissa_small  <= a_gtet_b ? mantissa_b : mantissa_a;
      mantissa_large  <= a_gtet_b ? mantissa_a : mantissa_b;
      small_is_denorm <= !(exponent_small > 0);
      large_is_denorm <= !(exponent_large > 0);
      large_norm_small_denorm <= (small_is_denorm == 1 && large_is_denorm == 0);
      small_is_nonzero <= (exponent_small > 0) | |mantissa_small[51:0];
      exponent_diff <= exponent_large - exponent_small - large_norm_small_denorm;
      minuend <= { !large_is_denorm, mantissa_large, 2'b00 };
      subtrahend <= { !small_is_denorm, mantissa_small, 2'b00 };
      subtra_shift <= subtrahend >> exponent_diff;
      subtra_shift_3 <= subtra_fraction_enable ? subtra_shift_2 : subtra_shift;
      diff_shift_2 <= diff_shift;
      diff <= minuend - subtra_shift_3;
      diffshift_gt_exponent <= diff_shift_2 > exponent_large;
      diffshift_et_55 <= diff_shift_2 == 55; 
      diff_1 <= diffshift_gt_exponent ? diff << exponent_large : diff << diff_shift_2;
      exponent <= diffshift_gt_exponent ? 0 : (exponent_large - diff_shift_2);
      exponent_2 <= diffshift_et_55 ? 0 : exponent;
      diff_2 <= in_norm_out_denorm ? { 1'b0, diff_1 >> 1} : {1'b0, diff_1};
      
    end
  end

  // Calculate diff_shift  
  always @(*) diff_shift = msb ? (54 - msb) : (diff ? 54 : 55);


  fpu_pri_encoder#(.WIDTH( WIDTH ), .WIDTH_LOG( WIDTH_LOG )) fe(diff, msb);

endmodule

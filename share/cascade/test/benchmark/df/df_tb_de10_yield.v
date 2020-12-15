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

`include "fpu_pri_encoder.v"
`include "fpu_exceptions.v"
`include "fpu_round.v"
`include "fpu_add.v"
`include "fpu_sub.v"
`include "fpu_mul.v"
`include "fpu_div.v"
`include "fpu_double.v"

module fpu_tb( clk );
  input wire clk;
  reg rst;
  reg enable;
  reg [1:0]rmode;
  reg [2:0]fpu_op;
  reg [63:0]opa;
  reg [63:0]opb;
  wire [63:0]out;
  wire ready;
  wire underflow;
  wire overflow;
  wire inexact;
  wire exception;
  wire invalid;

  (*non_volatile*)
  reg [31:0] ctr;
  (*non_volatile*)
  reg [31:0] test_ctr;
  
  (*non_volatile*)
  reg [63:0] out_reg;

  parameter TESTS_TO_RUN = 7500000;


  fpu UUT (
           .clk(clk),
           .rst(rst),
           .enable(enable),
           .rmode(rmode),
           .fpu_op(fpu_op),
           .opa(opa),
           .opb(opb),
           .out(out),
           .ready(ready),
           .underflow(underflow),
           .overflow(overflow),
           .inexact(inexact),
           .exception(exception),
           .invalid(invalid));

  initial begin
    ctr <= 0;
    rst <= 0;
    test_ctr <= 0;

  end

  always @(posedge clk) begin
    out_reg <= out;
    ctr <= ctr + 1;

    if (test_ctr >= TESTS_TO_RUN) begin
      //$display("Finished tests");
      $finish();
    end

    
    if (ctr == 0)
      rst <= 1'b1;
    else if (ctr == 2) begin
      rst <= 1'b0;     

      /******************************* ADDITION ******************************/      
      //$display("ADDITION!!");


      //inputA:2.2700000000e-001
      //inputB:3.4000000000e+001
      enable <= 1'b1;
      opa <= 64'b0011111111001101000011100101011000000100000110001001001101110101;
      opb <= 64'b0100000001000001000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 2)
    
    else if (ctr == 4) enable <= 1'b0;

    else if (ctr == 29) begin
      //Output:3.422700000000000e+001
      /*
      if (out==64'h40411d0e56041894)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);
      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */

      //inputA:-9.0300000000e+002
      //inputB:2.1000000000e+001
      enable <= 1'b1;
      opa <= 64'b1100000010001100001110000000000000000000000000000000000000000000;
      opb <= 64'b0100000000110101000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b00;
    end // else if (ctr == 29)

    else if (ctr == 31) enable <= 1'b0;

    else if (ctr == 56) begin
      //Output:-8.820000000000000e+002
      /*
      if (out==64'hc08b900000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);
      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */

      //inputA:-1.0000000000e-309
      //inputB:1.1000000000e-309
      enable <= 1'b1;
      opa <= 64'b1000000000000000101110000001010101110010011010001111110110101110;
      opb <= 64'b0000000000000000110010100111110111111101110110011110001111011001;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 56)

    else if (ctr == 58) enable <= 1'b0;

    else if (ctr == 83) begin
      //Output:9.999999999999969e-311
      /*
      if (out==64'h000012688b70e62b)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);
      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-4.0600000000e+001
      //inputB:-3.5700000000e+001
      enable <= 1'b1;
      opa <= 64'b1100000001000100010011001100110011001100110011001100110011001101;
      opb <= 64'b1100000001000001110110011001100110011001100110011001100110011010;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b00;
    end // else if (ctr == 83)

    else if (ctr == 85) enable <= 1'b0;

    else if (ctr == 110) begin
      //Output:-7.630000000000001e+001
      /*
      if (out==64'hc053133333333334)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);
      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:3.4500000000e+002
      //inputB:-3.4400000000e+002
      enable <= 1'b1;
      opa <= 64'b0100000001110101100100000000000000000000000000000000000000000000;
      opb <= 64'b1100000001110101100000000000000000000000000000000000000000000000;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 110)

    else if (ctr == 112) enable <= 1'b0;

    else if (ctr == 137) begin
      //Output:1.000000000000000e+000
      /*
      if (out==64'h3ff0000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);
      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:2.0000000000e-311
      //inputB:0.0000000000e+000
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000111010111010000010010010011100011110100010;
      opb <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b00;
    end // else if (ctr == 137)

    else if (ctr == 139) enable <= 1'b0;

    else if (ctr == 164) begin
      //Output:1.999999999999895e-311
      /*
      if (out==64'h000003ae8249c7a2)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:2.1000000000e-308
      //inputB:2.0000000000e-308
      enable <= 1'b1;
      opa <= 64'b0000000000001111000110011100001001100010100111001100111101010011;
      opb <= 64'b0000000000001110011000011010110011110000001100111101000110100100;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 164)

    else if (ctr == 166) enable <= 1'b0;

    else if (ctr == 191) begin
      //Output:4.100000000000000e-308
      /*
      if (out==64'h001d7b6f52d0a0f7)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:2.1000000000e-308
      //inputB:2.0000000000e-308
      enable <= 1'b1;
      opa <= 64'b0000000000001111000110011100001001100010100111001100111101010011;
      opb <= 64'b0000000000001110011000011010110011110000001100111101000110100100;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 191)

    else if (ctr == 193) enable <= 1'b0;

    else if (ctr == 218) begin
      //Output:4.100000000000000e-308
      /*
      if (out==64'h001d7b6f52d0a0f7)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:5.0000000000e-308
      //inputB:2.0000000000e-312
      enable <= 1'b1;
      opa <= 64'b0000000000100001111110100001100000101100010000001100011000001101;
      opb <= 64'b0000000000000000000000000101111001000000001110101001001111110110;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 218)

    else if (ctr == 220) enable <= 1'b0;

    else if (ctr == 245) begin
      //Output:5.000199999999999e-308
      /*
      if (out==64'h0021fa474c5e1008)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:3.9800000000e+000
      //inputB:3.7700000000e+000
      enable <= 1'b1;
      opa <= 64'b0100000000001111110101110000101000111101011100001010001111010111;
      opb <= 64'b0100000000001110001010001111010111000010100011110101110000101001;
      fpu_op <= 3'b000;  // addition
      rmode <= 2'b10;
    end // else if (ctr == 245)

    else if (ctr == 247) enable <= 1'b0;

    else if (ctr == 272) begin
      //Output:7.750000000000000e+000
      /*
      if (out==64'h401f000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.4000000000e+001
      //inputB:7.9000000000e-002
      enable <= 1'b1;
      opa <= 64'b0100000001000110000000000000000000000000000000000000000000000000;
      opb <= 64'b0011111110110100001110010101100000010000011000100100110111010011;
      fpu_op <= 3'b000;
      rmode <= 2'b00;
    end // else if (ctr == 272)

    else if (ctr == 274) enable <= 1'b0;

    else if (ctr == 299) begin
      //Output:4.407900000000000e+001
      /*
      if (out==64'h40460a1cac083127)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:3.0000000000e-310
      //inputB:4.0000000000e-304
      enable <= 1'b1;
      opa <= 64'b0000000000000000001101110011100110100010010100101011001010000001;
      opb <= 64'b0000000011110001100011100011101110011011001101110100000101101001;
      fpu_op <= 3'b000;  // add
      rmode <= 2'b10;
    end // else if (ctr == 299)

    else if (ctr == 301) enable <= 1'b0;

    else if (ctr == 326) begin
      //Output:4.000003000000000e-304
      /*
      if (out==64'h00f18e3c781dcab4)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      /******************************* SUBTRACTION ******************************/      

      //$display("SUBTRACTION");


      //inputA:4.6500000000e+002
      //inputB:6.5000000000e+001
      enable <= 1'b1;
      opa <= 64'b0100000001111101000100000000000000000000000000000000000000000000;
      opb <= 64'b0100000001010000010000000000000000000000000000000000000000000000;
      fpu_op <= 3'b001;  // subtraction
      rmode <= 2'b00;
    end // else if (ctr == 326)
    else if (ctr == 328) enable <= 1'b0;

    else if (ctr == 354) begin
      //Output:4.000000000000000e+002
      /*
      if (out==64'h4079000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-4.5000000000e+001
      //inputB:-3.2000000000e+001
      enable <= 1'b1;
      opa <= 64'b1100000001000110100000000000000000000000000000000000000000000000;
      opb <= 64'b1100000001000000000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b001;  // subtraction
      rmode <= 2'b11;
    end // else if (ctr == 354)

    else if (ctr == 356) enable <= 1'b0;

    else if (ctr == 382) begin
      //Output:-1.300000000000000e+001
      /*
      if (out==64'hc02a000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.0195000000e+002
      //inputB:-3.3600000000e+001
      enable <= 1'b1;
      opa <= 64'b0100000001111001000111110011001100110011001100110011001100110011;
      opb <= 64'b1100000001000000110011001100110011001100110011001100110011001101;
      fpu_op <= 3'b001;  // subtraction
      rmode <= 2'b11;
    end // else if (ctr == 382)

    else if (ctr == 384) enable <= 1'b0;

    else if (ctr == 410) begin
      //Output:4.355500000000000e+002
      /*
      if (out==64'h407b38cccccccccc)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.8999000000e+004
      //inputB:2.3600000000e+001
      enable <= 1'b1;
      opa <= 64'b0100000011100111111011001110000000000000000000000000000000000000;
      opb <= 64'b0100000000110111100110011001100110011001100110011001100110011010;
      fpu_op <= 3'b001;  // subtraction
      rmode <= 2'b10;
    end // else if (ctr == 410)

    else if (ctr == 412) enable <= 1'b0;

    else if (ctr == 438) begin
      //Output:4.897540000000000e+004
      /*
      if (out==64'h40e7e9eccccccccd)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:2.3770000000e+001
      //inputB:-4.5000000000e+001
      enable <= 1'b1;
      opa <= 64'b0100000000110111110001010001111010111000010100011110101110000101;
      opb <= 64'b1100000001000110100000000000000000000000000000000000000000000000;
      fpu_op <= 3'b001;  // subtraction
      rmode <= 2'b11;
    end // else if (ctr == 438)
    
    else if (ctr == 440) enable <= 1'b0;

    else if (ctr == 466) begin
      //Output:6.877000000000000e+001
      /*
      if (out==64'h40513147ae147ae1)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:5.6999990000e+006
      //inputB:5.6999989900e+006
      enable <= 1'b1;
      opa <= 64'b0100000101010101101111100110011111000000000000000000000000000000;
      opb <= 64'b0100000101010101101111100110011110111111010111000010100011110110;
      fpu_op <= 3'b001;  // sub
      rmode <= 2'b10;

    end // else if (ctr == 466)

    else if (ctr == 468) enable <= 1'b0;

    else if (ctr == 494) begin
      //Output:9.999999776482582e-003
      /*
      if (out==64'h3f847ae140000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-4.0000000000e+000
      //inputB:9.0000000000e+000
      enable <= 1'b1;
      opa <= 64'b1100000000010000000000000000000000000000000000000000000000000000;
      opb <= 64'b0100000000100010000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b001;  // sub
      rmode <= 2'b10;
    end // else if (ctr == 494)

    else if (ctr == 496) enable <= 1'b0;

    else if (ctr == 522) begin
      //Output:-1.300000000000000e+001
      /*
      if (out==64'hc02a000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:3.9700000000e+001
      //inputB:2.5700000000e-002
      enable <= 1'b1;
      opa <= 64'b0100000001000011110110011001100110011001100110011001100110011010;
      opb <= 64'b0011111110011010010100010001100111001110000001110101111101110000;
      fpu_op <= 3'b001;  // sub
      rmode <= 2'b10;

    end // else if (ctr == 522)

    else if (ctr == 524) enable <= 1'b0;

    else if (ctr == 550) begin
      //Output:3.967430000000001e+001
      /*
      if (out==64'h4043d64f765fd8af)
        $display("answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputa:2.3000000000e+000
      //inputb:7.0000000000e-002
      enable <= 1'b1;
      opa <= 64'b0100000000000010011001100110011001100110011001100110011001100110;
      opb <= 64'b0011111110110001111010111000010100011110101110000101000111101100;
      fpu_op <= 3'b001;  // sub
      rmode <= 2'b00;
    end // else if (ctr == 550)

    else if (ctr == 552) enable <= 1'b0;

    else if (ctr == 578) begin
      //output:2.230000000000000e+000
      /*
      if (out==64'h4001d70a3d70a3d7)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:1.9999999673e-316
      //inputB:1.9999999673e-317
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000000000000000000010011010011010111011000010;
      opb <= 64'b0000000000000000000000000000000000000000001111011100010010101101;
      fpu_op <= 3'b001;  // sub
      rmode <= 2'b00;
    end // else if (ctr == 578)

    else if (ctr == 580) enable <= 1'b0;

    else if (ctr == 606) begin
      //Output:1.799999970587486e-316
      /*
      if (out==64'h00000000022bea15)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:1.9999999970e-315
      //inputB:-1.9999999673e-316
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000000000000000011000001000001101001110011010;
      opb <= 64'b1000000000000000000000000000000000000010011010011010111011000010;
      fpu_op <= 3'b001; // sub
      rmode <= 2'b10;
    end // else if (ctr == 606)

    else if (ctr == 608) enable <= 1'b0;

    else if (ctr == 634) begin
      //Output:2.199999993695311e-315
      /*
      if (out==64'h000000001a8a825c)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.0000000000e+000
      //inputB:1.0000000000e-025
      enable <= 1'b1;
      opa <= 64'b0100000000010000000000000000000000000000000000000000000000000000;
      opb <= 64'b0011101010111110111100101101000011110101110110100111110111011001;
      fpu_op <= 3'b001;  // sub
      rmode <= 2'b10;

    end // else if (ctr == 634)

    else if (ctr == 636) enable <= 1'b0;

    else if (ctr == 662) begin
      //Output:4.000000000000000e+000
      /*
      if (out==64'h4010000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      /******************************* MULTIPLICATION ******************************/      

      //$display("MULTIPLICATION");

      
      //inputA:3.0000000000e-290
      //inputB:3.0000000000e-021
      enable <= 1'b1;
      opa <= 64'b0000001111010010101101100000010001001001010000101111100001010101;
      opb <= 64'b0011101110101100010101011000111000001111000101011110100011110111;
      fpu_op <= 3'b010;  // mul
      rmode <= 2'b10;

    end // else if (ctr == 662)

    else if (ctr == 664) enable <= 1'b0;

    // #800000;  // 80 cycles
    else if (ctr == 693) begin
      //Output:9.000000000000022e-311
      /*
      if (out==64'h000010914a4c025a)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-9.5000000000e+001
      //inputB:2.0000000000e+002
      enable <= 1'b1;
      opa <= 64'b1100000001010111110000000000000000000000000000000000000000000000;
      opb <= 64'b0100000001101001000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b010;  // multiplication
      rmode <= 2'b00;
    end // else if (ctr == 693)

    else if (ctr == 695) enable <= 1'b0;


    else if (ctr == 724) begin
      //Output:-1.900000000000000e+004
      /*
      if (out==64'hc0d28e0000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:2.3577000000e+002
      //inputB:2.0000000000e-002
      enable <= 1'b1;
      opa <= 64'b0100000001101101011110001010001111010111000010100011110101110001;
      opb <= 64'b0011111110010100011110101110000101000111101011100001010001111011;
      fpu_op <= 3'b010;  // multiplication
      rmode <= 2'b10;
    end // else if (ctr == 724)

    else if (ctr == 726) enable <= 1'b0;

    else if (ctr == 755) begin
      //Output:4.715400000000001e+000
      /*
      if (out==64'h4012dc91d14e3bce)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-4.7700000000e+002
      //inputB:4.8960000000e+002
      enable <= 1'b1;
      opa <= 64'b1100000001111101110100000000000000000000000000000000000000000000;
      opb <= 64'b0100000001111110100110011001100110011001100110011001100110011010;
      fpu_op <= 3'b010;  // multiplication
      rmode <= 2'b11;
    end // else if (ctr == 755)
    
    else if (ctr == 757) enable <= 1'b0;

    else if (ctr == 786) begin
      //Output:-2.335392000000000e+005
      /*
      if (out==64'hc10c82199999999a)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:0.0000000000e+000
      //inputB:9.0000000000e+050
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
      opb <= 64'b0100101010000011001111100111000010011110001011100011000100101101;
      fpu_op <= 3'b010;  // mult
      rmode <= 2'b10;
    end // else if (ctr == 786)

    else if (ctr == 788) enable <= 1'b0;

    else if (ctr == 817) begin
      //Output:0.000000000000000e+000
      /*
      if (out==64'h0000000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:5.0000000000e-311
      //inputB:9.0000000000e+009
      enable <= 1'b1;
      opa <= 64'b0000000000000000000010010011010001000101101110000111001100010101;
      opb <= 64'b0100001000000000110000111000100011010000000000000000000000000000;
      fpu_op <= 3'b010;  // mult
      rmode <= 2'b10;
    end // else if (ctr == 817)

    else if (ctr == 819) enable <= 1'b0;

    else if (ctr == 848) begin 
      //Output:4.499999999999764e-301
      /*
      if (out==64'h01934982fc467380)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-4.0000000000e-305
      //inputB:2.0000000000e-008
      enable <= 1'b1;
      opa <= 64'b1000000010111100000101101100010111000101001001010011010101110101;
      opb <= 64'b0011111001010101011110011000111011100010001100001000110000111010;
      fpu_op <= 3'b010;  // mult
      rmode <= 2'b11;
    end // else if (ctr == 848)

    else if (ctr == 850) enable <= 1'b0;

    else if (ctr == 879) begin 
      //Output:-8.000000000007485e-313
      /*
      if (out==64'h80000025b34aa196)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:3.0000000000e-308
      //inputB:1.0000000000e-012
      enable <= 1'b1;
      opa <= 64'b0000000000010101100100101000001101101000010011011011101001110111;
      opb <= 64'b0011110101110001100101111001100110000001001011011110101000010001;
      fpu_op <= 3'b010;  // mult
      rmode <= 2'b00;
    end // else if (ctr == 879)

    else if (ctr == 881) enable <= 1'b0;

    else if (ctr == 910) begin
      //Output:2.999966601548049e-320
      /*
      if (out==64'h00000000000017b8)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      /******************************* MULTIPLICATION ******************************/      

      //$display("DIVISION");
      
      //inputA:1.6999999999e-314
      //inputB:4.0000000000e-300
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000000000000011001101000101110000011010100010;
      opb <= 64'b0000000111000101011011100001111111000010111110001111001101011001;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b00;  // round up
    end // else if (ctr == 910)

    else if (ctr == 912) enable <= 1'b0;

    else if (ctr == 988) begin
      //Output:4.249999999722977e-015
      /*
      if (out==64'h3cf323ea98d06fb6) 
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */

      //inputA:2.2300000000e+002
      //inputB:5.6000000000e+001
      enable <= 1'b1;
      opa <= 64'b0100000001101011111000000000000000000000000000000000000000000000;
      opb <= 64'b0100000001001100000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b00;
    end // else if (ctr == 988)

    else if (ctr == 990) enable <= 1'b0;

    else if (ctr == 1066) begin
      //Output:3.982142857142857e+000
      /*
      if (out==64'h400fdb6db6db6db7)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.5500000000e+002
      //inputB:-4.5900000000e+002
      enable <= 1'b1;
      opa <= 64'b0100000001111100011100000000000000000000000000000000000000000000;
      opb <= 64'b1100000001111100101100000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b00;
    end // else if (ctr == 1066)

    else if (ctr == 1068) enable <= 1'b0;

    else if (ctr == 1144) begin
      //Output:-9.912854030501089e-001
      /*
      if (out==64'hbfefb89c2a6346d5)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.0000000000e-200
      //inputB:2.0000000000e+002
      enable <= 1'b1;
      opa <= 64'b0001011010001000011111101001001000010101010011101111011110101100;
      opb <= 64'b0100000001101001000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b00;
    end // else if (ctr == 1144)

    else if (ctr == 1146) enable <= 1'b0;

    else if (ctr == 1222) begin
      //Output:2.000000000000000e-202
      /*
      if (out==64'h160f5a549627a36c)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.0000000000e+020
      //inputB:2.0000000000e+002
      enable <= 1'b1;
      opa <= 64'b0100010000110101101011110001110101111000101101011000110001000000;
      opb <= 64'b0100000001101001000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b00;

    end // else if (ctr == 1222)

    else if (ctr == 1224) enable <= 1'b0;

    else if (ctr == 1300) begin
      //Output:2.000000000000000e+018
      /*
      if (out==64'h43bbc16d674ec800)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:5.0000000000e+000
      //inputB:2.5000000000e+000
      enable <= 1'b1;
      opa <= 64'b0100000000010100000000000000000000000000000000000000000000000000;
      opb <= 64'b0100000000000100000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b11;
    end // else if (ctr == 1300)

    else if (ctr == 1302) enable <= 1'b0;

    else if (ctr == 1378) begin
      //Output:2.000000000000000e+000
      /*
      if (out==64'h4000000000000000)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:1.0000000000e-312
      //inputB:1.0000000000e+000
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000000010111100100000000111010100100111111011;
      opb <= 64'b0011111111110000000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b10;
    end // else if (ctr == 1378)

    else if (ctr == 1380) enable <= 1'b0;

    else if (ctr == 1456) begin
      //Output:9.999999999984653e-313
      /*
      if (out==64'h0000002f201d49fb)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:4.0000000000e-200
      //inputB:3.0000000000e+111
      enable <= 1'b1;
      opa <= 64'b0001011010001000011111101001001000010101010011101111011110101100;
      opb <= 64'b0101011100010011111101011000110101000011010010100010101110101110;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b10;
    end // else if (ctr == 1456)

    else if (ctr == 1458) enable <= 1'b0;

    else if (ctr == 1534) begin
      //Output:1.333333333333758e-311
      /*
      if (out==64'h0000027456dbda6d)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:7.0000000000e-310
      //inputB:8.0000000000e-100
      enable <= 1'b1;
      opa <= 64'b0000000000000000100000001101101111010000000101100100101100101101;
      opb <= 64'b0010101101011011111111110010111011100100100011100000010100110000;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b11;
    end // else if (ctr == 1534)

    else if (ctr == 1536) enable <= 1'b0;

    else if (ctr == 1612) begin

      //Output:8.749999999999972e-211
      /*
      if (out==64'h14526914eebbd470)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:1.4000000000e-311
      //inputB:2.5000000000e-310
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000101001001111000001100110100000101110111110;
      opb <= 64'b0000000000000000001011100000010101011100100110100011111101101011;
      fpu_op <= 3'b011;  // division
      rmode <= 2'b00;
    end // else if (ctr == 1612)

    else if (ctr == 1614) enable <= 1'b0;

    else if (ctr == 1690) begin
      //Output:5.599999999999383e-002
      /*
      if (out==64'h3facac083126e600)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */

      //inputA:-6.7000000000e+001
      //inputB:0.0000000000e+000
      enable <= 1'b1;
      opa <= 64'b1100000001010000110000000000000000000000000000000000000000000000;
      opb <= 64'b0000000000000000000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b10;
    end // else if (ctr == 1690)

    else if (ctr == 1692) enable <= 1'b0;

    else if (ctr == 1768) begin
      //Output:-1.#INF00000000000e+000
      /*
      if (out==64'hffefffffffffffff)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-4.5600000000e+001
      //inputB:-6.9000000000e+001
      enable <= 1'b1;
      opa <= 64'b1100000001000110110011001100110011001100110011001100110011001101;
      opb <= 64'b1100000001010001010000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b00;
    end // else if (ctr == 1768)

    else if (ctr == 1770) enable <= 1'b0;

    else if (ctr == 1846) begin
      //Output:6.608695652173914e-001
      /*
      if (out==64'h3fe525d7ee30f953)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-5.9900000000e+002
      //inputB:2.7000000000e-002
      enable <= 1'b1;
      opa <= 64'b1100000010000010101110000000000000000000000000000000000000000000;
      opb <= 64'b0011111110011011101001011110001101010011111101111100111011011001;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b00;
    end // else if (ctr == 1846)

    else if (ctr == 1848) enable <= 1'b0;

    else if (ctr == 1924) begin
      //Output:-2.218518518518519e+004
      /*
      if (out==64'hc0d5aa4bda12f685)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:3.5000000000e-313
      //inputB:7.0000000000e+004
      enable <= 1'b1;
      opa <= 64'b0000000000000000000000000001000001111110011100001010011010110001;
      opb <= 64'b0100000011110001000101110000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b00;
    end // else if (ctr == 1924)

    else if (ctr == 1926) enable <= 1'b0;

    else if (ctr == 2002) begin
      //Output:4.999998683134458e-318
      /*
      if (out==64'h00000000000f712b)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-5.1000000000e-306
      //inputB:2.0480000000e+003
      enable <= 1'b1;
      opa <= 64'b1000000010001100101001101001011010000110100001110011101110100101;
      opb <= 64'b0100000010100000000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b11;
    end // else if (ctr == 2002)

    else if (ctr == 2004) enable <= 1'b0;

    else if (ctr == 2080) begin
      //Output:-2.490234375000003e-309
      /*
      if (out==64'h8001ca69686873bb)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-1.5000000000e-305
      //inputB:1.0240000000e+003
      enable <= 1'b1;
      opa <= 64'b1000000010100101000100010001010001010011110110111110100000011000;
      opb <= 64'b0100000010010000000000000000000000000000000000000000000000000000;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b11;
    end // else if (ctr == 2080)

    else if (ctr == 2082) enable <= 1'b0;

    else if (ctr == 2158) begin
      //Output:-1.464843750000000e-308
      /*
      if (out==64'h800a888a29edf40c)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:-3.4000000000e+056
      //inputB:-4.0000000000e+199
      enable <= 1'b1;
      opa <= 64'b1100101110101011101110111000100000000000101110111001110000000101;
      opb <= 64'b1110100101100000101110001110000010101100101011000100111010101111;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b00;
    end // else if (ctr == 2158)

    else if (ctr == 2160) enable <= 1'b0;

    else if (ctr == 2236) begin

      //Output:8.500000000000000e-144
      /*
      if (out==64'h223a88ecc2ac8317)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */


      //inputA:1.3559000000e-001
      //inputB:2.3111240000e+003
      enable <= 1'b1;
      opa <= 64'b0011111111000001010110110000001101011011110101010001001011101100;
      opb <= 64'b0100000010100010000011100011111101111100111011011001000101101000;
      fpu_op <= 3'b011;  // div
      rmode <= 2'b00;

    end // else if (ctr == 2236)

    else if (ctr == 2238) enable <= 1'b0;

    else if (ctr == 2314) begin
      //Output:5.866842281071894e-005
      /*
      if (out==64'h3f0ec257a882625f)
        $display("Answer is correct %h%h", out[63:32], out[31:0]);

      else
        $display("Error! out is incorrect %h%h", out[63:32], out[31:0]);
      */

    end

    else if (ctr > 2400) begin
      test_ctr <= test_ctr + 1;
      ctr <= 0;  // reset ctr for another iteration through tests
      //$display(test_ctr);
    end
    
    if (ctr > 2400) $yield;

  end // always @ (posedge clk)

endmodule

fpu_tb ft( clock.val );

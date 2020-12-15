module fpu_pri_encoder#(
  parameter WIDTH = 106, 
  parameter WIDTH_LOG = 7                 
)(
  value,
  msb
);

  input wire [WIDTH - 1 : 0] value;
  output wire [WIDTH_LOG:0] msb;

  genvar i;

  for (i = 0; i < WIDTH_LOG; i = i + 1) begin : ORS
    wire [(1 << WIDTH_LOG) - 1:0] oi;
    wire msbi;

    if (i == 0)
      assign oi = value;
    else
      assign oi[(1 << (WIDTH_LOG - i)) - 1:0] = ORS[i - 1].msbi ? ORS[i - 1].oi[2 * (1 << (WIDTH_LOG - i)) - 1:(1 << (WIDTH_LOG - i))] : ORS[i - 1].oi[(1 << (WIDTH_LOG - i)) - 1 : 0];

    assign msbi = |oi[2 * (1 << (WIDTH_LOG - 1 - i)) - 1: (1 << (WIDTH_LOG - 1 - i))];
    assign msb[WIDTH_LOG - 1 - i] = |oi[2 * (1 << (WIDTH_LOG - 1 - i)) - 1: (1 << (WIDTH_LOG - 1 - i))];
    
  end


endmodule // fpu_pri_encoder

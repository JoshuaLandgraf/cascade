localparam x = 8;
localparam y = 0;

initial begin
  $write(y <= x);
  $write(x <= x-1);
  $finish;
end


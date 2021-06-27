module soft_fifo #(
	parameter WIDTH = 64,
	parameter LOG_DEPTH = 1
) (
	input clk,
	input rst,
	
	input wrreq,
	input [WIDTH-1:0] din,
	output full,
	
	input rdreq,
	output [WIDTH-1:0] dout,
	output empty
);

// FIFO memory
reg [WIDTH-1:0] mem [(1<<LOG_DEPTH)-1:0];

// metadata
reg [LOG_DEPTH-1:0] wr_ptr = 0;
reg [LOG_DEPTH-1:0] rd_ptr = 0;
reg [LOG_DEPTH:0] size = 0;

// I/O signals
wire full_ = size[LOG_DEPTH];
wire empty_ = size == 0;
assign full = full_;
assign empty = empty_;
assign dout = mem[rd_ptr];

// register update logic
always @(posedge clk) begin
	if (rst) begin
		wr_ptr <= 0;
		rd_ptr <= 0;
		size <= 0;
	end else begin
		// size reg update
		if (rdreq && !empty_ && wrreq && !full_) begin
		end else if (rdreq && !empty_) begin
			size <= size - 1;
		end else if (wrreq && !full_) begin
			size <= size + 1;
		end
		// pointer and mem update
		if (rdreq && !empty_) begin
			rd_ptr <= rd_ptr + 1;
		end
		if (wrreq && !full_) begin
			mem[wr_ptr] <= din;
			wr_ptr <= wr_ptr + 1;
		end
	end
end

endmodule

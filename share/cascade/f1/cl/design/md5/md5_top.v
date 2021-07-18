module md5_top (
	input clk,
	input rst,
	
	output reg [15:0] arid_m,
	output reg [63:0] araddr_m,
	output reg [7:0]  arlen_m,
	output reg [2:0]  arsize_m,
	output reg        arvalid_m,
	input             arready_m,
	
	input [15:0]  rid_m,
	input [511:0] rdata_m,
	input [1:0]   rresp_m,
	input         rlast_m,
	input         rvalid_m,
	output        rready_m,
	
	output reg [15:0] awid_m,
	output reg [63:0] awaddr_m,
	output reg [7:0]  awlen_m,
	output reg [2:0]  awsize_m,
	output reg        awvalid_m,
	input             awready_m,
	
	output [15:0]  wid_m,
	output [511:0] wdata_m,
	output [63:0]  wstrb_m,
	output         wlast_m,
	output         wvalid_m,
	input          wready_m,
	
	input [15:0] bid_m,
	input [1:0]  bresp_m,
	input        bvalid_m,
	output       bready_m,
	
	input        softreg_req_valid,
	input        softreg_req_isWrite,
	input [31:0] softreg_req_addr,
	input [63:0] softreg_req_data,
	
	output reg        softreg_resp_valid,
	output reg [63:0] softreg_resp_data
);
parameter app_num = 0;

//// Input data stream
// state and signals
reg [63:0] id_addr;
reg [63:0] id_words;
reg [4:0] id_credits;
wire id_consume;

// FIFO signals
wire idf_wrreq = rvalid_m;
wire [511:0] idf_din = rdata_m;
wire idf_full;
wire idf_rdreq;
wire [511:0] idf_dout;
wire idf_empty;
assign rready_m = !idf_full;
assign id_consume = rvalid_m && rready_m && rlast_m;

// logic
reg [6:0] id_len_addr;
reg [6:0] id_len_words;
reg [6:0] id_len;
always @(*) begin
	arid_m = 0;
	araddr_m = id_addr;
	//arlen_m = 0;
	arsize_m = 3'b110;
	arvalid_m = id_words && id_credits;
	
	id_len_addr = 7'd64 - id_addr[5:0];
	id_len_words = (id_words < id_len_addr) ? id_words : id_len_addr;
	id_len = id_len_words;
	
	arlen_m = id_len - 1;
end
always @(posedge clk) begin
	if (rst) begin
		id_addr <= 0;
		id_words <= 0;
		id_credits <= 8;
	end else begin
		if (arvalid_m && arready_m) begin
			id_addr <= id_addr + (id_len << 6);
			id_words <= id_words - id_len;
		end
		if ((arvalid_m && arready_m) && id_consume) begin
			// Do nothing
		end else if (arvalid_m && arready_m) begin
			id_credits <= id_credits - 1;
		end else if (id_consume) begin
			id_credits <= id_credits + 1;
		end else begin
			// Do nothing
		end
		if (softreg_req_valid && softreg_req_isWrite) begin
			case (softreg_req_addr)
				32'h10: id_addr <= softreg_req_data;
				32'h18: id_credits <= softreg_req_data;
				32'h20: id_words <= softreg_req_data;
			endcase
		end
	end
end

// instantiations
/*
soft_fifo #(
	.WIDTH(512),
	.LOG_DEPTH(2)
) input_data_fifo (
	.clk(clk),
	.rst(rst),
	.wrreq(idf_wrreq),
	.din(idf_din),
	.full(idf_full),
	.rdreq(idf_rdreq),
	.dout(idf_dout),
	.empty(idf_empty)
);*/
HullFIFO #(
	.TYPE(0),
	.WIDTH(512),
	.LOG_DEPTH(2)
) input_data_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(idf_wrreq),
	.data(idf_din),
	.full(idf_full),
	.rdreq(idf_rdreq),
	.q(idf_dout),
	.empty(idf_empty)
);


//// MD5 core
// state and signals
reg [63:0] md5_valid;
reg [63:0] md5_words;
wire md5_in_valid = !idf_empty;
wire md5_out_valid = md5_valid[63];

reg [31:0] md5_a_reg;
reg [31:0] md5_b_reg;
reg [31:0] md5_c_reg;
reg [31:0] md5_d_reg;
wire [31:0] md5_a;
wire [31:0] md5_b;
wire [31:0] md5_c;
wire [31:0] md5_d;
wire [511:0] md5_chunk = idf_dout;

// logic
assign idf_rdreq = 1;
always @(posedge clk) begin
	if (rst) begin
		md5_valid <= 0;
	end else begin
		md5_valid <= {md5_valid[62:0], md5_in_valid};
		if (md5_out_valid) begin
			md5_a_reg <= md5_a_reg + md5_a;
			md5_b_reg <= md5_b_reg + md5_b;
			md5_c_reg <= md5_c_reg + md5_c;
			md5_d_reg <= md5_d_reg + md5_d;
			md5_words <= md5_words + 1;
		end
		if (softreg_req_valid && softreg_req_isWrite) begin
			case (softreg_req_addr)
				32'h20: begin
					md5_a_reg <= 0;
					md5_b_reg <= 0;
					md5_c_reg <= 0;
					md5_d_reg <= 0;
					md5_words <= 0;
				end
			endcase
		end
	end
end

// instantiation
Md5Core m (
	.clk(clk),
	.wb(md5_chunk),
	.a0('h67452301),
	.b0('hefcdab89),
	.c0('h98badcfe),
	.d0('h10325476),
	.a64(md5_a),
	.b64(md5_b),
	.c64(md5_c),
	.d64(md5_d)
);


//// SoftReg output
always @(posedge clk) begin
	if (rst) begin
		softreg_resp_valid <= 0;
		softreg_resp_data <= 0;
	end else begin
		softreg_resp_valid <= softreg_req_valid && !softreg_req_isWrite;
		case (softreg_req_addr)
			32'h00: softreg_resp_data <= {md5_b_reg, md5_a_reg};
			32'h08: softreg_resp_data <= {md5_d_reg, md5_c_reg};
			32'h28: softreg_resp_data <= md5_words;
		endcase
	end
end

endmodule

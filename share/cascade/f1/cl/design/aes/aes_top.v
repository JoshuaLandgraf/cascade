module aes_top (
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

//// AES stream
// state and signals
reg [63:0] aes_words;
reg [6:0] aes_credit;
reg [30:0] aes_valid;
reg [61:0] aes_seq;
reg [255:0] aes_key;
reg [511:0] aes_out_reg;
wire [511:0] aes_out;
wire aes_consume;

// FIFO signals
wire aef_wrreq = aes_valid[0];
wire [511:0] aef_din = aes_out_reg;
wire aef_full;  // unused
wire aef_rdreq;
wire [511:0] aef_dout;
wire aef_empty;

// logic
always @(posedge clk) begin
	if (rst) begin
		aes_words <= 0;
		aes_credit <= 32;
		aes_valid <= 0;
		aes_seq <= 0;
		aes_key <= 0;
		aes_out_reg <= 0;
	end else begin
		aes_valid <= (aes_valid >> 1);
		if ((aes_words > 0) && (aes_credit > 0)) begin
			aes_words <= aes_words - 1;
			aes_valid[30] <= 1;
			aes_seq <= aes_seq + 1;
		end
		if ((aes_words && aes_credit) && aes_consume) begin
			// do nothing
		end else if (aes_words && aes_credit) begin
			aes_credit <= aes_credit - 1;
		end else if (aes_consume) begin
			aes_credit <= aes_credit + 1;
		end else begin
			// do nothing
		end
		aes_out_reg <= aes_out;
		if (softreg_req_valid && softreg_req_isWrite) begin
			case (softreg_req_addr)
				32'h00: aes_key[63:0] <= softreg_req_data;
				32'h08: aes_key[127:64] <= softreg_req_data;
				32'h10: aes_key[191:128] <= softreg_req_data;
				32'h18: aes_key[255:192] <= softreg_req_data;
				32'h30: begin
					aes_words <= softreg_req_data;
					aes_seq <= 0;
				end
			endcase
		end
	end
end

// instantiations
aes_256 aes0 (
	.clk(clk),
	.state({64'h0000000000000000, aes_seq, 2'h0}),
	.key(aes_key),
	.out(aes_out[127:0])
);
aes_256 aes1 (
	.clk(clk),
	.state({64'h0000000000000000, aes_seq, 2'h1}),
	.key(aes_key),
	.out(aes_out[255:128])
);
aes_256 aes2 (
	.clk(clk),
	.state({64'h0000000000000000, aes_seq, 2'h2}),
	.key(aes_key),
	.out(aes_out[383:256])
);
aes_256 aes3 (
	.clk(clk),
	.state({64'h0000000000000000, aes_seq, 2'h3}),
	.key(aes_key),
	.out(aes_out[511:384])
);
HullFIFO #(
	.TYPE(3),
	.WIDTH(512),
	.LOG_DEPTH(5)
) aes_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(aef_wrreq),
	.data(aef_din),
	.full(aef_full),
	.rdreq(aef_rdreq),
	.q(aef_dout),
	.empty(aef_empty)
);


//// Input data stream
// state and signals
reg [63:0] id_addr;
reg [63:0] id_words;
reg [8:0] id_credits;
wire id_consume;

// FIFO signals
wire idf_wrreq = rvalid_m;
wire [511:0] idf_din = rdata_m;
wire idf_full;
wire idf_rdreq;
wire [511:0] idf_dout;
wire idf_empty;
assign rready_m = !idf_full;

// logic
reg [6:0] id_len_addr;
reg [6:0] id_len_words;
reg [6:0] id_len;
always @(*) begin
	arid_m = 0;
	araddr_m = id_addr;
	//arlen_m = 0;
	arsize_m = 3'b110;
	arvalid_m = id_words && (id_credits >= 64);
	
	id_len_addr = 7'd64 - id_addr[5:0];
	id_len_words = (id_words < id_len_addr) ? id_words : id_len_addr;
	id_len = id_len_words;
	
	arlen_m = id_len - 1;
end
always @(posedge clk) begin
	if (rst) begin
		id_addr <= 0;
		id_words <= 0;
		id_credits <= 511;
	end else begin
		if (arvalid_m && arready_m) begin
			id_addr <= id_addr + (id_len << 6);
			id_words <= id_words - id_len;
			id_credits <= id_credits - id_len + id_consume;
		end else begin
			id_credits <= id_credits + id_consume;
		end
		if (softreg_req_valid && softreg_req_isWrite) begin
			case (softreg_req_addr)
				32'h20: id_addr <= softreg_req_data;
				32'h30: id_words <= softreg_req_data;
			endcase
		end
	end
end

// instantiations
HullFIFO #(
	.TYPE(3),
	.WIDTH(512),
	.LOG_DEPTH(9)
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


// Output metadata stream
// state and signals
reg [63:0] om_addr;
reg [63:0] om_words;

// logic
reg [6:0] om_len_addr;
reg [6:0] om_len_words;
reg [6:0] om_len;
always @(*) begin
	awid_m = 0;
	awaddr_m = om_addr;
	//awlen_m = 0;
	awsize_m = 3'b110;
	awvalid_m = (om_words > 0);
	
	om_len_addr = 7'd64 - om_addr[5:0];
	om_len_words = (om_words < om_len_addr) ? om_words : om_len_addr;
	om_len = om_len_words;
	
	awlen_m = om_len - 1;
end
always @(posedge clk) begin
	if (rst) begin
		om_addr <= 0;
		om_words <= 0;
	end else begin
		if (awvalid_m && awready_m) begin
			om_addr <= om_addr + (om_len << 6);
			om_words <= om_words - om_len;
		end
		if (softreg_req_valid && softreg_req_isWrite) begin
			case (softreg_req_addr)
				32'h28: om_addr <= softreg_req_data;
				32'h30: om_words <= softreg_req_data;
			endcase
		end
	end
end


//// Output data stream
// state and signals
reg [63:0] od_addr;
reg [63:0] od_words;

// FIFO signals
wire odf_wrreq = !aef_empty && !idf_empty;
wire [511:0] odf_din = aef_dout ^ idf_dout;
wire odf_full;
wire odf_rdreq = wready_m;
wire [511:0] odf_dout;
wire odf_empty;

// misc signals
wire od_intake = !aef_empty && !idf_empty && !odf_full;
assign aes_consume = od_intake;
assign id_consume = od_intake;
assign aef_rdreq = !idf_empty && !odf_full;
assign idf_rdreq = !aef_empty && !odf_full;

// logic
assign wid_m = 0;
assign wdata_m = odf_dout;
assign wstrb_m = 64'hFFFFFFFFFFFFFFFF;
assign wlast_m = (od_addr[11:6] == 6'h3F) || (od_words == 0);
assign wvalid_m = !odf_empty;
assign bready_m = 1;

always @(posedge clk) begin
	if (rst) begin
		od_addr <= 0;
		od_words <= 0;
	end else begin
		if (!odf_empty && wready_m) begin
			od_addr <= od_addr + 64;
			od_words <= od_words - 1;
		end
		if (softreg_req_valid && softreg_req_isWrite) begin
			case (softreg_req_addr)
				32'h28: od_addr <= softreg_req_data;
				32'h30: od_words <= softreg_req_data;
			endcase
		end
	end
end

// instantiations
HullFIFO #(
	.TYPE(3),
	.WIDTH(512),
	.LOG_DEPTH(6)
) output_data_fifo (
	.clock(clk),
	.reset_n(~rst),
	.wrreq(odf_wrreq),
	.data(odf_din),
	.full(odf_full),
	.rdreq(odf_rdreq),
	.q(odf_dout),
	.empty(odf_empty)
);


//// SoftReg output
always @(posedge clk) begin
	if (rst) begin
		softreg_resp_valid <= 0;
		softreg_resp_data <= 0;
	end else begin
		softreg_resp_valid <= softreg_req_valid && !softreg_req_isWrite;
		softreg_resp_data <= od_words;
	end
end


endmodule

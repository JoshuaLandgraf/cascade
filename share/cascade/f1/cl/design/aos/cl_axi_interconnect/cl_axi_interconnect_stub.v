// Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2019.1.op (lin64) Build 2552052 Fri May 24 14:47:09 MDT 2019
// Date        : Fri Apr  2 15:19:38 2021
// Host        : ip-172-31-37-101.ec2.internal running 64-bit CentOS Linux release 7.7.1908 (Core)
// Command     : write_verilog -force -mode synth_stub
//               /home/centos/src/project_data/vivado_project/project_2/project_2.srcs/sources_1/bd/cl_axi_interconnect/cl_axi_interconnect_stub.v
// Design      : cl_axi_interconnect
// Purpose     : Stub declaration of top-level module interface
// Device      : xcvu9p-flgb2104-2-i
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
module cl_axi_interconnect(ACLK, ARESETN, M00_AXI_araddr, M00_AXI_arburst, 
  M00_AXI_arcache, M00_AXI_arid, M00_AXI_arlen, M00_AXI_arlock, M00_AXI_arprot, 
  M00_AXI_arqos, M00_AXI_arready, M00_AXI_arregion, M00_AXI_arsize, M00_AXI_arvalid, 
  M00_AXI_awaddr, M00_AXI_awburst, M00_AXI_awcache, M00_AXI_awid, M00_AXI_awlen, 
  M00_AXI_awlock, M00_AXI_awprot, M00_AXI_awqos, M00_AXI_awready, M00_AXI_awregion, 
  M00_AXI_awsize, M00_AXI_awvalid, M00_AXI_bid, M00_AXI_bready, M00_AXI_bresp, 
  M00_AXI_bvalid, M00_AXI_rdata, M00_AXI_rid, M00_AXI_rlast, M00_AXI_rready, M00_AXI_rresp, 
  M00_AXI_rvalid, M00_AXI_wdata, M00_AXI_wlast, M00_AXI_wready, M00_AXI_wstrb, 
  M00_AXI_wvalid, M01_AXI_araddr, M01_AXI_arburst, M01_AXI_arcache, M01_AXI_arid, 
  M01_AXI_arlen, M01_AXI_arlock, M01_AXI_arprot, M01_AXI_arqos, M01_AXI_arready, 
  M01_AXI_arregion, M01_AXI_arsize, M01_AXI_arvalid, M01_AXI_awaddr, M01_AXI_awburst, 
  M01_AXI_awcache, M01_AXI_awid, M01_AXI_awlen, M01_AXI_awlock, M01_AXI_awprot, 
  M01_AXI_awqos, M01_AXI_awready, M01_AXI_awregion, M01_AXI_awsize, M01_AXI_awvalid, 
  M01_AXI_bid, M01_AXI_bready, M01_AXI_bresp, M01_AXI_bvalid, M01_AXI_rdata, M01_AXI_rid, 
  M01_AXI_rlast, M01_AXI_rready, M01_AXI_rresp, M01_AXI_rvalid, M01_AXI_wdata, M01_AXI_wlast, 
  M01_AXI_wready, M01_AXI_wstrb, M01_AXI_wvalid, M02_AXI_araddr, M02_AXI_arburst, 
  M02_AXI_arcache, M02_AXI_arid, M02_AXI_arlen, M02_AXI_arlock, M02_AXI_arprot, 
  M02_AXI_arqos, M02_AXI_arready, M02_AXI_arregion, M02_AXI_arsize, M02_AXI_arvalid, 
  M02_AXI_awaddr, M02_AXI_awburst, M02_AXI_awcache, M02_AXI_awid, M02_AXI_awlen, 
  M02_AXI_awlock, M02_AXI_awprot, M02_AXI_awqos, M02_AXI_awready, M02_AXI_awregion, 
  M02_AXI_awsize, M02_AXI_awvalid, M02_AXI_bid, M02_AXI_bready, M02_AXI_bresp, 
  M02_AXI_bvalid, M02_AXI_rdata, M02_AXI_rid, M02_AXI_rlast, M02_AXI_rready, M02_AXI_rresp, 
  M02_AXI_rvalid, M02_AXI_wdata, M02_AXI_wlast, M02_AXI_wready, M02_AXI_wstrb, 
  M02_AXI_wvalid, M03_AXI_araddr, M03_AXI_arburst, M03_AXI_arcache, M03_AXI_arid, 
  M03_AXI_arlen, M03_AXI_arlock, M03_AXI_arprot, M03_AXI_arqos, M03_AXI_arready, 
  M03_AXI_arregion, M03_AXI_arsize, M03_AXI_arvalid, M03_AXI_awaddr, M03_AXI_awburst, 
  M03_AXI_awcache, M03_AXI_awid, M03_AXI_awlen, M03_AXI_awlock, M03_AXI_awprot, 
  M03_AXI_awqos, M03_AXI_awready, M03_AXI_awregion, M03_AXI_awsize, M03_AXI_awvalid, 
  M03_AXI_bid, M03_AXI_bready, M03_AXI_bresp, M03_AXI_bvalid, M03_AXI_rdata, M03_AXI_rid, 
  M03_AXI_rlast, M03_AXI_rready, M03_AXI_rresp, M03_AXI_rvalid, M03_AXI_wdata, M03_AXI_wlast, 
  M03_AXI_wready, M03_AXI_wstrb, M03_AXI_wvalid, S00_AXI_araddr, S00_AXI_arburst, 
  S00_AXI_arcache, S00_AXI_arid, S00_AXI_arlen, S00_AXI_arlock, S00_AXI_arprot, 
  S00_AXI_arqos, S00_AXI_arready, S00_AXI_arregion, S00_AXI_arsize, S00_AXI_arvalid, 
  S00_AXI_awaddr, S00_AXI_awburst, S00_AXI_awcache, S00_AXI_awid, S00_AXI_awlen, 
  S00_AXI_awlock, S00_AXI_awprot, S00_AXI_awqos, S00_AXI_awready, S00_AXI_awregion, 
  S00_AXI_awsize, S00_AXI_awvalid, S00_AXI_bid, S00_AXI_bready, S00_AXI_bresp, 
  S00_AXI_bvalid, S00_AXI_rdata, S00_AXI_rid, S00_AXI_rlast, S00_AXI_rready, S00_AXI_rresp, 
  S00_AXI_rvalid, S00_AXI_wdata, S00_AXI_wlast, S00_AXI_wready, S00_AXI_wstrb, 
  S00_AXI_wvalid, S01_AXI_araddr, S01_AXI_arburst, S01_AXI_arcache, S01_AXI_arid, 
  S01_AXI_arlen, S01_AXI_arlock, S01_AXI_arprot, S01_AXI_arqos, S01_AXI_arready, 
  S01_AXI_arregion, S01_AXI_arsize, S01_AXI_arvalid, S01_AXI_awaddr, S01_AXI_awburst, 
  S01_AXI_awcache, S01_AXI_awid, S01_AXI_awlen, S01_AXI_awlock, S01_AXI_awprot, 
  S01_AXI_awqos, S01_AXI_awready, S01_AXI_awregion, S01_AXI_awsize, S01_AXI_awvalid, 
  S01_AXI_bid, S01_AXI_bready, S01_AXI_bresp, S01_AXI_bvalid, S01_AXI_rdata, S01_AXI_rid, 
  S01_AXI_rlast, S01_AXI_rready, S01_AXI_rresp, S01_AXI_rvalid, S01_AXI_wdata, S01_AXI_wlast, 
  S01_AXI_wready, S01_AXI_wstrb, S01_AXI_wvalid, S02_AXI_araddr, S02_AXI_arburst, 
  S02_AXI_arcache, S02_AXI_arid, S02_AXI_arlen, S02_AXI_arlock, S02_AXI_arprot, 
  S02_AXI_arqos, S02_AXI_arready, S02_AXI_arregion, S02_AXI_arsize, S02_AXI_arvalid, 
  S02_AXI_awaddr, S02_AXI_awburst, S02_AXI_awcache, S02_AXI_awid, S02_AXI_awlen, 
  S02_AXI_awlock, S02_AXI_awprot, S02_AXI_awqos, S02_AXI_awready, S02_AXI_awregion, 
  S02_AXI_awsize, S02_AXI_awvalid, S02_AXI_bid, S02_AXI_bready, S02_AXI_bresp, 
  S02_AXI_bvalid, S02_AXI_rdata, S02_AXI_rid, S02_AXI_rlast, S02_AXI_rready, S02_AXI_rresp, 
  S02_AXI_rvalid, S02_AXI_wdata, S02_AXI_wlast, S02_AXI_wready, S02_AXI_wstrb, 
  S02_AXI_wvalid, S03_AXI_araddr, S03_AXI_arburst, S03_AXI_arcache, S03_AXI_arid, 
  S03_AXI_arlen, S03_AXI_arlock, S03_AXI_arprot, S03_AXI_arqos, S03_AXI_arready, 
  S03_AXI_arregion, S03_AXI_arsize, S03_AXI_arvalid, S03_AXI_awaddr, S03_AXI_awburst, 
  S03_AXI_awcache, S03_AXI_awid, S03_AXI_awlen, S03_AXI_awlock, S03_AXI_awprot, 
  S03_AXI_awqos, S03_AXI_awready, S03_AXI_awregion, S03_AXI_awsize, S03_AXI_awvalid, 
  S03_AXI_bid, S03_AXI_bready, S03_AXI_bresp, S03_AXI_bvalid, S03_AXI_rdata, S03_AXI_rid, 
  S03_AXI_rlast, S03_AXI_rready, S03_AXI_rresp, S03_AXI_rvalid, S03_AXI_wdata, S03_AXI_wlast, 
  S03_AXI_wready, S03_AXI_wstrb, S03_AXI_wvalid, S04_AXI_araddr, S04_AXI_arburst, 
  S04_AXI_arcache, S04_AXI_arid, S04_AXI_arlen, S04_AXI_arlock, S04_AXI_arprot, 
  S04_AXI_arqos, S04_AXI_arready, S04_AXI_arregion, S04_AXI_arsize, S04_AXI_arvalid, 
  S04_AXI_awaddr, S04_AXI_awburst, S04_AXI_awcache, S04_AXI_awid, S04_AXI_awlen, 
  S04_AXI_awlock, S04_AXI_awprot, S04_AXI_awqos, S04_AXI_awready, S04_AXI_awregion, 
  S04_AXI_awsize, S04_AXI_awvalid, S04_AXI_bid, S04_AXI_bready, S04_AXI_bresp, 
  S04_AXI_bvalid, S04_AXI_rdata, S04_AXI_rid, S04_AXI_rlast, S04_AXI_rready, S04_AXI_rresp, 
  S04_AXI_rvalid, S04_AXI_wdata, S04_AXI_wlast, S04_AXI_wready, S04_AXI_wstrb, 
  S04_AXI_wvalid)
/* synthesis syn_black_box black_box_pad_pin="ACLK,ARESETN,M00_AXI_araddr[63:0],M00_AXI_arburst[1:0],M00_AXI_arcache[3:0],M00_AXI_arid[8:0],M00_AXI_arlen[7:0],M00_AXI_arlock[0:0],M00_AXI_arprot[2:0],M00_AXI_arqos[3:0],M00_AXI_arready,M00_AXI_arregion[3:0],M00_AXI_arsize[2:0],M00_AXI_arvalid,M00_AXI_awaddr[63:0],M00_AXI_awburst[1:0],M00_AXI_awcache[3:0],M00_AXI_awid[8:0],M00_AXI_awlen[7:0],M00_AXI_awlock[0:0],M00_AXI_awprot[2:0],M00_AXI_awqos[3:0],M00_AXI_awready,M00_AXI_awregion[3:0],M00_AXI_awsize[2:0],M00_AXI_awvalid,M00_AXI_bid[8:0],M00_AXI_bready,M00_AXI_bresp[1:0],M00_AXI_bvalid,M00_AXI_rdata[511:0],M00_AXI_rid[8:0],M00_AXI_rlast,M00_AXI_rready,M00_AXI_rresp[1:0],M00_AXI_rvalid,M00_AXI_wdata[511:0],M00_AXI_wlast,M00_AXI_wready,M00_AXI_wstrb[63:0],M00_AXI_wvalid,M01_AXI_araddr[63:0],M01_AXI_arburst[1:0],M01_AXI_arcache[3:0],M01_AXI_arid[8:0],M01_AXI_arlen[7:0],M01_AXI_arlock[0:0],M01_AXI_arprot[2:0],M01_AXI_arqos[3:0],M01_AXI_arready,M01_AXI_arregion[3:0],M01_AXI_arsize[2:0],M01_AXI_arvalid,M01_AXI_awaddr[63:0],M01_AXI_awburst[1:0],M01_AXI_awcache[3:0],M01_AXI_awid[8:0],M01_AXI_awlen[7:0],M01_AXI_awlock[0:0],M01_AXI_awprot[2:0],M01_AXI_awqos[3:0],M01_AXI_awready,M01_AXI_awregion[3:0],M01_AXI_awsize[2:0],M01_AXI_awvalid,M01_AXI_bid[8:0],M01_AXI_bready,M01_AXI_bresp[1:0],M01_AXI_bvalid,M01_AXI_rdata[511:0],M01_AXI_rid[8:0],M01_AXI_rlast,M01_AXI_rready,M01_AXI_rresp[1:0],M01_AXI_rvalid,M01_AXI_wdata[511:0],M01_AXI_wlast,M01_AXI_wready,M01_AXI_wstrb[63:0],M01_AXI_wvalid,M02_AXI_araddr[63:0],M02_AXI_arburst[1:0],M02_AXI_arcache[3:0],M02_AXI_arid[8:0],M02_AXI_arlen[7:0],M02_AXI_arlock[0:0],M02_AXI_arprot[2:0],M02_AXI_arqos[3:0],M02_AXI_arready,M02_AXI_arregion[3:0],M02_AXI_arsize[2:0],M02_AXI_arvalid,M02_AXI_awaddr[63:0],M02_AXI_awburst[1:0],M02_AXI_awcache[3:0],M02_AXI_awid[8:0],M02_AXI_awlen[7:0],M02_AXI_awlock[0:0],M02_AXI_awprot[2:0],M02_AXI_awqos[3:0],M02_AXI_awready,M02_AXI_awregion[3:0],M02_AXI_awsize[2:0],M02_AXI_awvalid,M02_AXI_bid[8:0],M02_AXI_bready,M02_AXI_bresp[1:0],M02_AXI_bvalid,M02_AXI_rdata[511:0],M02_AXI_rid[8:0],M02_AXI_rlast,M02_AXI_rready,M02_AXI_rresp[1:0],M02_AXI_rvalid,M02_AXI_wdata[511:0],M02_AXI_wlast,M02_AXI_wready,M02_AXI_wstrb[63:0],M02_AXI_wvalid,M03_AXI_araddr[63:0],M03_AXI_arburst[1:0],M03_AXI_arcache[3:0],M03_AXI_arid[8:0],M03_AXI_arlen[7:0],M03_AXI_arlock[0:0],M03_AXI_arprot[2:0],M03_AXI_arqos[3:0],M03_AXI_arready,M03_AXI_arregion[3:0],M03_AXI_arsize[2:0],M03_AXI_arvalid,M03_AXI_awaddr[63:0],M03_AXI_awburst[1:0],M03_AXI_awcache[3:0],M03_AXI_awid[8:0],M03_AXI_awlen[7:0],M03_AXI_awlock[0:0],M03_AXI_awprot[2:0],M03_AXI_awqos[3:0],M03_AXI_awready,M03_AXI_awregion[3:0],M03_AXI_awsize[2:0],M03_AXI_awvalid,M03_AXI_bid[8:0],M03_AXI_bready,M03_AXI_bresp[1:0],M03_AXI_bvalid,M03_AXI_rdata[511:0],M03_AXI_rid[8:0],M03_AXI_rlast,M03_AXI_rready,M03_AXI_rresp[1:0],M03_AXI_rvalid,M03_AXI_wdata[511:0],M03_AXI_wlast,M03_AXI_wready,M03_AXI_wstrb[63:0],M03_AXI_wvalid,S00_AXI_araddr[63:0],S00_AXI_arburst[1:0],S00_AXI_arcache[3:0],S00_AXI_arid[5:0],S00_AXI_arlen[7:0],S00_AXI_arlock[0:0],S00_AXI_arprot[2:0],S00_AXI_arqos[3:0],S00_AXI_arready,S00_AXI_arregion[3:0],S00_AXI_arsize[2:0],S00_AXI_arvalid,S00_AXI_awaddr[63:0],S00_AXI_awburst[1:0],S00_AXI_awcache[3:0],S00_AXI_awid[5:0],S00_AXI_awlen[7:0],S00_AXI_awlock[0:0],S00_AXI_awprot[2:0],S00_AXI_awqos[3:0],S00_AXI_awready,S00_AXI_awregion[3:0],S00_AXI_awsize[2:0],S00_AXI_awvalid,S00_AXI_bid[5:0],S00_AXI_bready,S00_AXI_bresp[1:0],S00_AXI_bvalid,S00_AXI_rdata[511:0],S00_AXI_rid[5:0],S00_AXI_rlast,S00_AXI_rready,S00_AXI_rresp[1:0],S00_AXI_rvalid,S00_AXI_wdata[511:0],S00_AXI_wlast,S00_AXI_wready,S00_AXI_wstrb[63:0],S00_AXI_wvalid,S01_AXI_araddr[63:0],S01_AXI_arburst[1:0],S01_AXI_arcache[3:0],S01_AXI_arid[5:0],S01_AXI_arlen[7:0],S01_AXI_arlock[0:0],S01_AXI_arprot[2:0],S01_AXI_arqos[3:0],S01_AXI_arready,S01_AXI_arregion[3:0],S01_AXI_arsize[2:0],S01_AXI_arvalid,S01_AXI_awaddr[63:0],S01_AXI_awburst[1:0],S01_AXI_awcache[3:0],S01_AXI_awid[5:0],S01_AXI_awlen[7:0],S01_AXI_awlock[0:0],S01_AXI_awprot[2:0],S01_AXI_awqos[3:0],S01_AXI_awready,S01_AXI_awregion[3:0],S01_AXI_awsize[2:0],S01_AXI_awvalid,S01_AXI_bid[5:0],S01_AXI_bready,S01_AXI_bresp[1:0],S01_AXI_bvalid,S01_AXI_rdata[511:0],S01_AXI_rid[5:0],S01_AXI_rlast,S01_AXI_rready,S01_AXI_rresp[1:0],S01_AXI_rvalid,S01_AXI_wdata[511:0],S01_AXI_wlast,S01_AXI_wready,S01_AXI_wstrb[63:0],S01_AXI_wvalid,S02_AXI_araddr[63:0],S02_AXI_arburst[1:0],S02_AXI_arcache[3:0],S02_AXI_arid[5:0],S02_AXI_arlen[7:0],S02_AXI_arlock[0:0],S02_AXI_arprot[2:0],S02_AXI_arqos[3:0],S02_AXI_arready,S02_AXI_arregion[3:0],S02_AXI_arsize[2:0],S02_AXI_arvalid,S02_AXI_awaddr[63:0],S02_AXI_awburst[1:0],S02_AXI_awcache[3:0],S02_AXI_awid[5:0],S02_AXI_awlen[7:0],S02_AXI_awlock[0:0],S02_AXI_awprot[2:0],S02_AXI_awqos[3:0],S02_AXI_awready,S02_AXI_awregion[3:0],S02_AXI_awsize[2:0],S02_AXI_awvalid,S02_AXI_bid[5:0],S02_AXI_bready,S02_AXI_bresp[1:0],S02_AXI_bvalid,S02_AXI_rdata[511:0],S02_AXI_rid[5:0],S02_AXI_rlast,S02_AXI_rready,S02_AXI_rresp[1:0],S02_AXI_rvalid,S02_AXI_wdata[511:0],S02_AXI_wlast,S02_AXI_wready,S02_AXI_wstrb[63:0],S02_AXI_wvalid,S03_AXI_araddr[63:0],S03_AXI_arburst[1:0],S03_AXI_arcache[3:0],S03_AXI_arid[5:0],S03_AXI_arlen[7:0],S03_AXI_arlock[0:0],S03_AXI_arprot[2:0],S03_AXI_arqos[3:0],S03_AXI_arready,S03_AXI_arregion[3:0],S03_AXI_arsize[2:0],S03_AXI_arvalid,S03_AXI_awaddr[63:0],S03_AXI_awburst[1:0],S03_AXI_awcache[3:0],S03_AXI_awid[5:0],S03_AXI_awlen[7:0],S03_AXI_awlock[0:0],S03_AXI_awprot[2:0],S03_AXI_awqos[3:0],S03_AXI_awready,S03_AXI_awregion[3:0],S03_AXI_awsize[2:0],S03_AXI_awvalid,S03_AXI_bid[5:0],S03_AXI_bready,S03_AXI_bresp[1:0],S03_AXI_bvalid,S03_AXI_rdata[511:0],S03_AXI_rid[5:0],S03_AXI_rlast,S03_AXI_rready,S03_AXI_rresp[1:0],S03_AXI_rvalid,S03_AXI_wdata[511:0],S03_AXI_wlast,S03_AXI_wready,S03_AXI_wstrb[63:0],S03_AXI_wvalid,S04_AXI_araddr[63:0],S04_AXI_arburst[1:0],S04_AXI_arcache[3:0],S04_AXI_arid[5:0],S04_AXI_arlen[7:0],S04_AXI_arlock[0:0],S04_AXI_arprot[2:0],S04_AXI_arqos[3:0],S04_AXI_arready,S04_AXI_arregion[3:0],S04_AXI_arsize[2:0],S04_AXI_arvalid,S04_AXI_awaddr[63:0],S04_AXI_awburst[1:0],S04_AXI_awcache[3:0],S04_AXI_awid[5:0],S04_AXI_awlen[7:0],S04_AXI_awlock[0:0],S04_AXI_awprot[2:0],S04_AXI_awqos[3:0],S04_AXI_awready,S04_AXI_awregion[3:0],S04_AXI_awsize[2:0],S04_AXI_awvalid,S04_AXI_bid[5:0],S04_AXI_bready,S04_AXI_bresp[1:0],S04_AXI_bvalid,S04_AXI_rdata[511:0],S04_AXI_rid[5:0],S04_AXI_rlast,S04_AXI_rready,S04_AXI_rresp[1:0],S04_AXI_rvalid,S04_AXI_wdata[511:0],S04_AXI_wlast,S04_AXI_wready,S04_AXI_wstrb[63:0],S04_AXI_wvalid" */;
  input ACLK;
  input ARESETN;
  output [63:0]M00_AXI_araddr;
  output [1:0]M00_AXI_arburst;
  output [3:0]M00_AXI_arcache;
  output [8:0]M00_AXI_arid;
  output [7:0]M00_AXI_arlen;
  output [0:0]M00_AXI_arlock;
  output [2:0]M00_AXI_arprot;
  output [3:0]M00_AXI_arqos;
  input M00_AXI_arready;
  output [3:0]M00_AXI_arregion;
  output [2:0]M00_AXI_arsize;
  output M00_AXI_arvalid;
  output [63:0]M00_AXI_awaddr;
  output [1:0]M00_AXI_awburst;
  output [3:0]M00_AXI_awcache;
  output [8:0]M00_AXI_awid;
  output [7:0]M00_AXI_awlen;
  output [0:0]M00_AXI_awlock;
  output [2:0]M00_AXI_awprot;
  output [3:0]M00_AXI_awqos;
  input M00_AXI_awready;
  output [3:0]M00_AXI_awregion;
  output [2:0]M00_AXI_awsize;
  output M00_AXI_awvalid;
  input [8:0]M00_AXI_bid;
  output M00_AXI_bready;
  input [1:0]M00_AXI_bresp;
  input M00_AXI_bvalid;
  input [511:0]M00_AXI_rdata;
  input [8:0]M00_AXI_rid;
  input M00_AXI_rlast;
  output M00_AXI_rready;
  input [1:0]M00_AXI_rresp;
  input M00_AXI_rvalid;
  output [511:0]M00_AXI_wdata;
  output M00_AXI_wlast;
  input M00_AXI_wready;
  output [63:0]M00_AXI_wstrb;
  output M00_AXI_wvalid;
  output [63:0]M01_AXI_araddr;
  output [1:0]M01_AXI_arburst;
  output [3:0]M01_AXI_arcache;
  output [8:0]M01_AXI_arid;
  output [7:0]M01_AXI_arlen;
  output [0:0]M01_AXI_arlock;
  output [2:0]M01_AXI_arprot;
  output [3:0]M01_AXI_arqos;
  input M01_AXI_arready;
  output [3:0]M01_AXI_arregion;
  output [2:0]M01_AXI_arsize;
  output M01_AXI_arvalid;
  output [63:0]M01_AXI_awaddr;
  output [1:0]M01_AXI_awburst;
  output [3:0]M01_AXI_awcache;
  output [8:0]M01_AXI_awid;
  output [7:0]M01_AXI_awlen;
  output [0:0]M01_AXI_awlock;
  output [2:0]M01_AXI_awprot;
  output [3:0]M01_AXI_awqos;
  input M01_AXI_awready;
  output [3:0]M01_AXI_awregion;
  output [2:0]M01_AXI_awsize;
  output M01_AXI_awvalid;
  input [8:0]M01_AXI_bid;
  output M01_AXI_bready;
  input [1:0]M01_AXI_bresp;
  input M01_AXI_bvalid;
  input [511:0]M01_AXI_rdata;
  input [8:0]M01_AXI_rid;
  input M01_AXI_rlast;
  output M01_AXI_rready;
  input [1:0]M01_AXI_rresp;
  input M01_AXI_rvalid;
  output [511:0]M01_AXI_wdata;
  output M01_AXI_wlast;
  input M01_AXI_wready;
  output [63:0]M01_AXI_wstrb;
  output M01_AXI_wvalid;
  output [63:0]M02_AXI_araddr;
  output [1:0]M02_AXI_arburst;
  output [3:0]M02_AXI_arcache;
  output [8:0]M02_AXI_arid;
  output [7:0]M02_AXI_arlen;
  output [0:0]M02_AXI_arlock;
  output [2:0]M02_AXI_arprot;
  output [3:0]M02_AXI_arqos;
  input M02_AXI_arready;
  output [3:0]M02_AXI_arregion;
  output [2:0]M02_AXI_arsize;
  output M02_AXI_arvalid;
  output [63:0]M02_AXI_awaddr;
  output [1:0]M02_AXI_awburst;
  output [3:0]M02_AXI_awcache;
  output [8:0]M02_AXI_awid;
  output [7:0]M02_AXI_awlen;
  output [0:0]M02_AXI_awlock;
  output [2:0]M02_AXI_awprot;
  output [3:0]M02_AXI_awqos;
  input M02_AXI_awready;
  output [3:0]M02_AXI_awregion;
  output [2:0]M02_AXI_awsize;
  output M02_AXI_awvalid;
  input [8:0]M02_AXI_bid;
  output M02_AXI_bready;
  input [1:0]M02_AXI_bresp;
  input M02_AXI_bvalid;
  input [511:0]M02_AXI_rdata;
  input [8:0]M02_AXI_rid;
  input M02_AXI_rlast;
  output M02_AXI_rready;
  input [1:0]M02_AXI_rresp;
  input M02_AXI_rvalid;
  output [511:0]M02_AXI_wdata;
  output M02_AXI_wlast;
  input M02_AXI_wready;
  output [63:0]M02_AXI_wstrb;
  output M02_AXI_wvalid;
  output [63:0]M03_AXI_araddr;
  output [1:0]M03_AXI_arburst;
  output [3:0]M03_AXI_arcache;
  output [8:0]M03_AXI_arid;
  output [7:0]M03_AXI_arlen;
  output [0:0]M03_AXI_arlock;
  output [2:0]M03_AXI_arprot;
  output [3:0]M03_AXI_arqos;
  input M03_AXI_arready;
  output [3:0]M03_AXI_arregion;
  output [2:0]M03_AXI_arsize;
  output M03_AXI_arvalid;
  output [63:0]M03_AXI_awaddr;
  output [1:0]M03_AXI_awburst;
  output [3:0]M03_AXI_awcache;
  output [8:0]M03_AXI_awid;
  output [7:0]M03_AXI_awlen;
  output [0:0]M03_AXI_awlock;
  output [2:0]M03_AXI_awprot;
  output [3:0]M03_AXI_awqos;
  input M03_AXI_awready;
  output [3:0]M03_AXI_awregion;
  output [2:0]M03_AXI_awsize;
  output M03_AXI_awvalid;
  input [8:0]M03_AXI_bid;
  output M03_AXI_bready;
  input [1:0]M03_AXI_bresp;
  input M03_AXI_bvalid;
  input [511:0]M03_AXI_rdata;
  input [8:0]M03_AXI_rid;
  input M03_AXI_rlast;
  output M03_AXI_rready;
  input [1:0]M03_AXI_rresp;
  input M03_AXI_rvalid;
  output [511:0]M03_AXI_wdata;
  output M03_AXI_wlast;
  input M03_AXI_wready;
  output [63:0]M03_AXI_wstrb;
  output M03_AXI_wvalid;
  input [63:0]S00_AXI_araddr;
  input [1:0]S00_AXI_arburst;
  input [3:0]S00_AXI_arcache;
  input [5:0]S00_AXI_arid;
  input [7:0]S00_AXI_arlen;
  input [0:0]S00_AXI_arlock;
  input [2:0]S00_AXI_arprot;
  input [3:0]S00_AXI_arqos;
  output S00_AXI_arready;
  input [3:0]S00_AXI_arregion;
  input [2:0]S00_AXI_arsize;
  input S00_AXI_arvalid;
  input [63:0]S00_AXI_awaddr;
  input [1:0]S00_AXI_awburst;
  input [3:0]S00_AXI_awcache;
  input [5:0]S00_AXI_awid;
  input [7:0]S00_AXI_awlen;
  input [0:0]S00_AXI_awlock;
  input [2:0]S00_AXI_awprot;
  input [3:0]S00_AXI_awqos;
  output S00_AXI_awready;
  input [3:0]S00_AXI_awregion;
  input [2:0]S00_AXI_awsize;
  input S00_AXI_awvalid;
  output [5:0]S00_AXI_bid;
  input S00_AXI_bready;
  output [1:0]S00_AXI_bresp;
  output S00_AXI_bvalid;
  output [511:0]S00_AXI_rdata;
  output [5:0]S00_AXI_rid;
  output S00_AXI_rlast;
  input S00_AXI_rready;
  output [1:0]S00_AXI_rresp;
  output S00_AXI_rvalid;
  input [511:0]S00_AXI_wdata;
  input S00_AXI_wlast;
  output S00_AXI_wready;
  input [63:0]S00_AXI_wstrb;
  input S00_AXI_wvalid;
  input [63:0]S01_AXI_araddr;
  input [1:0]S01_AXI_arburst;
  input [3:0]S01_AXI_arcache;
  input [5:0]S01_AXI_arid;
  input [7:0]S01_AXI_arlen;
  input [0:0]S01_AXI_arlock;
  input [2:0]S01_AXI_arprot;
  input [3:0]S01_AXI_arqos;
  output S01_AXI_arready;
  input [3:0]S01_AXI_arregion;
  input [2:0]S01_AXI_arsize;
  input S01_AXI_arvalid;
  input [63:0]S01_AXI_awaddr;
  input [1:0]S01_AXI_awburst;
  input [3:0]S01_AXI_awcache;
  input [5:0]S01_AXI_awid;
  input [7:0]S01_AXI_awlen;
  input [0:0]S01_AXI_awlock;
  input [2:0]S01_AXI_awprot;
  input [3:0]S01_AXI_awqos;
  output S01_AXI_awready;
  input [3:0]S01_AXI_awregion;
  input [2:0]S01_AXI_awsize;
  input S01_AXI_awvalid;
  output [5:0]S01_AXI_bid;
  input S01_AXI_bready;
  output [1:0]S01_AXI_bresp;
  output S01_AXI_bvalid;
  output [511:0]S01_AXI_rdata;
  output [5:0]S01_AXI_rid;
  output S01_AXI_rlast;
  input S01_AXI_rready;
  output [1:0]S01_AXI_rresp;
  output S01_AXI_rvalid;
  input [511:0]S01_AXI_wdata;
  input S01_AXI_wlast;
  output S01_AXI_wready;
  input [63:0]S01_AXI_wstrb;
  input S01_AXI_wvalid;
  input [63:0]S02_AXI_araddr;
  input [1:0]S02_AXI_arburst;
  input [3:0]S02_AXI_arcache;
  input [5:0]S02_AXI_arid;
  input [7:0]S02_AXI_arlen;
  input [0:0]S02_AXI_arlock;
  input [2:0]S02_AXI_arprot;
  input [3:0]S02_AXI_arqos;
  output S02_AXI_arready;
  input [3:0]S02_AXI_arregion;
  input [2:0]S02_AXI_arsize;
  input S02_AXI_arvalid;
  input [63:0]S02_AXI_awaddr;
  input [1:0]S02_AXI_awburst;
  input [3:0]S02_AXI_awcache;
  input [5:0]S02_AXI_awid;
  input [7:0]S02_AXI_awlen;
  input [0:0]S02_AXI_awlock;
  input [2:0]S02_AXI_awprot;
  input [3:0]S02_AXI_awqos;
  output S02_AXI_awready;
  input [3:0]S02_AXI_awregion;
  input [2:0]S02_AXI_awsize;
  input S02_AXI_awvalid;
  output [5:0]S02_AXI_bid;
  input S02_AXI_bready;
  output [1:0]S02_AXI_bresp;
  output S02_AXI_bvalid;
  output [511:0]S02_AXI_rdata;
  output [5:0]S02_AXI_rid;
  output S02_AXI_rlast;
  input S02_AXI_rready;
  output [1:0]S02_AXI_rresp;
  output S02_AXI_rvalid;
  input [511:0]S02_AXI_wdata;
  input S02_AXI_wlast;
  output S02_AXI_wready;
  input [63:0]S02_AXI_wstrb;
  input S02_AXI_wvalid;
  input [63:0]S03_AXI_araddr;
  input [1:0]S03_AXI_arburst;
  input [3:0]S03_AXI_arcache;
  input [5:0]S03_AXI_arid;
  input [7:0]S03_AXI_arlen;
  input [0:0]S03_AXI_arlock;
  input [2:0]S03_AXI_arprot;
  input [3:0]S03_AXI_arqos;
  output S03_AXI_arready;
  input [3:0]S03_AXI_arregion;
  input [2:0]S03_AXI_arsize;
  input S03_AXI_arvalid;
  input [63:0]S03_AXI_awaddr;
  input [1:0]S03_AXI_awburst;
  input [3:0]S03_AXI_awcache;
  input [5:0]S03_AXI_awid;
  input [7:0]S03_AXI_awlen;
  input [0:0]S03_AXI_awlock;
  input [2:0]S03_AXI_awprot;
  input [3:0]S03_AXI_awqos;
  output S03_AXI_awready;
  input [3:0]S03_AXI_awregion;
  input [2:0]S03_AXI_awsize;
  input S03_AXI_awvalid;
  output [5:0]S03_AXI_bid;
  input S03_AXI_bready;
  output [1:0]S03_AXI_bresp;
  output S03_AXI_bvalid;
  output [511:0]S03_AXI_rdata;
  output [5:0]S03_AXI_rid;
  output S03_AXI_rlast;
  input S03_AXI_rready;
  output [1:0]S03_AXI_rresp;
  output S03_AXI_rvalid;
  input [511:0]S03_AXI_wdata;
  input S03_AXI_wlast;
  output S03_AXI_wready;
  input [63:0]S03_AXI_wstrb;
  input S03_AXI_wvalid;
  input [63:0]S04_AXI_araddr;
  input [1:0]S04_AXI_arburst;
  input [3:0]S04_AXI_arcache;
  input [5:0]S04_AXI_arid;
  input [7:0]S04_AXI_arlen;
  input [0:0]S04_AXI_arlock;
  input [2:0]S04_AXI_arprot;
  input [3:0]S04_AXI_arqos;
  output S04_AXI_arready;
  input [3:0]S04_AXI_arregion;
  input [2:0]S04_AXI_arsize;
  input S04_AXI_arvalid;
  input [63:0]S04_AXI_awaddr;
  input [1:0]S04_AXI_awburst;
  input [3:0]S04_AXI_awcache;
  input [5:0]S04_AXI_awid;
  input [7:0]S04_AXI_awlen;
  input [0:0]S04_AXI_awlock;
  input [2:0]S04_AXI_awprot;
  input [3:0]S04_AXI_awqos;
  output S04_AXI_awready;
  input [3:0]S04_AXI_awregion;
  input [2:0]S04_AXI_awsize;
  input S04_AXI_awvalid;
  output [5:0]S04_AXI_bid;
  input S04_AXI_bready;
  output [1:0]S04_AXI_bresp;
  output S04_AXI_bvalid;
  output [511:0]S04_AXI_rdata;
  output [5:0]S04_AXI_rid;
  output S04_AXI_rlast;
  input S04_AXI_rready;
  output [1:0]S04_AXI_rresp;
  output S04_AXI_rvalid;
  input [511:0]S04_AXI_wdata;
  input S04_AXI_wlast;
  output S04_AXI_wready;
  input [63:0]S04_AXI_wstrb;
  input S04_AXI_wvalid;
endmodule
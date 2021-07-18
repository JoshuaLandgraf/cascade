# Amazon FPGA Hardware Development Kit
#
# Copyright 2016 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Amazon Software License (the "License"). You may not use
# this file except in compliance with the License. A copy of the License is
# located at
#
#    http://aws.amazon.com/asl/
#
# or in the "license" file accompanying this file. This file is distributed on
# an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, express or
# implied. See the License for the specific language governing permissions and
# limitations under the License.

# TODO:
# Add check if CL_DIR and HDK_SHELL_DIR directories exist
# Add check if /build and /build/src_port_encryption directories exist
# Add check if the vivado_keyfile exist

set HDK_SHELL_DIR $::env(HDK_SHELL_DIR)
set HDK_SHELL_DESIGN_DIR $::env(HDK_SHELL_DESIGN_DIR)
set CL_DIR $::env(CL_DIR)
set TARGET_DIR $CL_DIR/build/src_post_encryption
set UNUSED_TEMPLATES_DIR $HDK_SHELL_DESIGN_DIR/interfaces
# Remove any previously encrypted files, that may no longer be used
if {[llength [glob -nocomplain -dir $TARGET_DIR *]] != 0} {
  eval file delete -force [glob $TARGET_DIR/*]
}

#---- Developr would replace this section with design files ----

# Remove any previously encrypted files, that may no longer be used
exec rm -f $TARGET_DIR/*

## Change file names and paths below to reflect your CL area.  DO NOT include AWS RTL files.
#---- Developer would replace this section with design files ----

file copy -force $CL_DIR/design/cl_aos_defines.vh $TARGET_DIR
file copy -force $CL_DIR/design/cl_id_defines.vh $TARGET_DIR
file copy -force $CL_DIR/design/cl_common_defines.vh $TARGET_DIR 
file copy -force $UNUSED_TEMPLATES_DIR/cl_ports.vh  $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_apppf_irq_template.inc  $TARGET_DIR
#file copy -force $UNUSED_TEMPLATES_DIR/unused_aurora_template.inc     $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_cl_sda_template.inc     $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_ddr_a_b_d_template.inc  $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_ddr_c_template.inc      $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_dma_pcis_template.inc   $TARGET_DIR
#file copy -force $UNUSED_TEMPLATES_DIR/unused_hmc_template.inc        $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_pcim_template.inc       $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_sh_bar1_template.inc    $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_flr_template.inc        $TARGET_DIR
file copy -force $UNUSED_TEMPLATES_DIR/unused_sh_ocl_template.inc        $TARGET_DIR
# AmorphOS
file copy -force $CL_DIR/design/aos/ShellTypes.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AMITypes.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AOSF1Types.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/FIFO.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/SoftFIFO.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/HullFIFO.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/TwoInputMux.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/FourInputMux.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/EightInputMux.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/ChannelArbiter.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/OneHotEncoder.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/OneHotMux.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/BlockBuffer.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/Counter64.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/ChannelArbiter.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AddressTranslate.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AppLevelTranslate.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/ChannelMerge.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/FourInputArbiter.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/MemDrive.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/MemDrive_SoftReg.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/RRWCArbiter.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/RespMerge.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/TwoInputArbiter.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AmorphOSSoftReg.sv $TARGET_DIR
#file copy -force $CL_DIR/design/aos/AmorphOSPCIE.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AmorphOSMem.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AmorphOSMem2SDRAM.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/PCIS_Loopback.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/PCIS_Write_Packet.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/PCIS_Read_Packet.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/PCIM_Loopback.sv $TARGET_DIR
# DRAM, DMA, TLB
file copy -force $CL_DIR/design/aos/cl_dram_dma_pkg.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/cl_dma_pcis_slv.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/DRAM_Loopback.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/axi_tlb.sv $TARGET_DIR
# F1 interfaces
file copy -force $CL_DIR/design/aos/AXIL2SR.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AXIL2SR_Extended.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/F1SoftRegLoopback.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AMI2AXI4_RdPath.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AMI2AXI4_WrPath.sv $TARGET_DIR
file copy -force $CL_DIR/design/aos/AMI2AXI4.sv $TARGET_DIR
# Tree Modules
file copy -force $CL_DIR/design/aos/AmorphOSSoftReg_RouteTree.sv $TARGET_DIR
#Cascade
file copy -force $CL_DIR/design/UserParams.sv $TARGET_DIR
file copy -force $CL_DIR/design/cascade_wrapper.sv $TARGET_DIR
file copy -force $CL_DIR/design/program_logic.v $TARGET_DIR
#AES
file copy -force $CL_DIR/design/aes/aes_wrapper.sv $TARGET_DIR
file copy -force $CL_DIR/design/aes/aes_top.v $TARGET_DIR
file copy -force $CL_DIR/design/aes/aes_256.v $TARGET_DIR
file copy -force $CL_DIR/design/aes/round.v $TARGET_DIR
file copy -force $CL_DIR/design/aes/table.v $TARGET_DIR
#MD5
file copy -force $CL_DIR/design/md5/md5_wrapper.sv $TARGET_DIR
file copy -force $CL_DIR/design/md5/md5_top.v $TARGET_DIR
file copy -force $CL_DIR/design/md5/Md5Core.v $TARGET_DIR
# Top level module
file copy -force $CL_DIR/design/cl_aos.sv                      $TARGET_DIR

#---- End of section replaced by Developr ---

# Make sure files have write permissions for the encryption
exec chmod +w {*}[glob $TARGET_DIR/*]

set TOOL_VERSION $::env(VIVADO_TOOL_VERSION)
set vivado_version [string range [version -short] 0 5]
puts "AWS FPGA: VIVADO_TOOL_VERSION $TOOL_VERSION"
puts "vivado_version $vivado_version"

# encrypt .v/.sv/.vh/inc as verilog files
#encrypt -k $HDK_SHELL_DIR/build/scripts/vivado_keyfile_2017_4.txt -lang verilog  [glob -nocomplain -- $TARGET_DIR/*.{v,sv}] [glob -nocomplain -- $TARGET_DIR/*.vh] [glob -nocomplain -- $TARGET_DIR/*.inc]
# encrypt *vhdl files
#encrypt -k $HDK_SHELL_DIR/build/scripts/vivado_vhdl_keyfile_2017_4.txt -lang vhdl -quiet [ glob -nocomplain -- $TARGET_DIR/*.vhd? ]

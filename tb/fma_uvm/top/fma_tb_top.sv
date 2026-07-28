// SPDX-License-Identifier: SHL-0.51

`ifndef FMA_NUM_PIPE_REGS
  `define FMA_NUM_PIPE_REGS 0
`endif

`ifndef FMA_PIPE_CONFIG
  `define FMA_PIPE_CONFIG 0
`endif

module fma_tb_top;
  timeunit 1ns;
  timeprecision 1ps;

  import uvm_pkg::*;
  import fpnew_pkg::*;
  import fma_config_pkg::*;
  import fma_test_pkg::*;

  localparam int unsigned NumPipeRegs = `FMA_NUM_PIPE_REGS;
  localparam fpnew_pkg::pipe_config_t PipeConfig = fpnew_pkg::pipe_config_t'(`FMA_PIPE_CONFIG);
  localparam int unsigned ExtRegEnaWidth = NumPipeRegs == 0 ? 1 : NumPipeRegs;

  logic clk_i;
  fma_if vif(.clk_i(clk_i));

  fpnew_fma #(
    .FpFormat    (FMA_FORMAT),
    .NumPipeRegs (NumPipeRegs),
    .PipeConfig  (PipeConfig),
    .TagType     (fma_tag_t),
    .AuxType     (fma_aux_t)
  ) dut (
    .clk_i,
    .rst_ni            (vif.rst_ni),
    .operands_i        (vif.operands_i),
    .is_boxed_i        (vif.is_boxed_i),
    .rnd_mode_i        (vif.rnd_mode_i),
    .op_i              (vif.op_i),
    .op_mod_i          (vif.op_mod_i),
    .tag_i             (vif.tag_i),
    .mask_i            (vif.mask_i),
    .aux_i             (vif.aux_i),
    .in_valid_i        (vif.in_valid_i),
    .in_ready_o        (vif.in_ready_o),
    .flush_i           (vif.flush_i),
    .result_o          (vif.result_o),
    .status_o          (vif.status_o),
    .extension_bit_o   (vif.extension_bit_o),
    .tag_o             (vif.tag_o),
    .mask_o            (vif.mask_o),
    .aux_o             (vif.aux_o),
    .out_valid_o       (vif.out_valid_o),
    .out_ready_i       (vif.out_ready_i),
    .busy_o            (vif.busy_o),
    .reg_ena_i         (vif.reg_ena_i[ExtRegEnaWidth-1:0]),
    .early_out_valid_o (vif.early_out_valid_o)
  );

  fma_protocol_checker i_fma_protocol_checker(vif);

  initial begin
    clk_i = 1'b0;
    forever #5ns clk_i = ~clk_i;
  end

  // Only time-zero safe values are supplied here.  After UVM starts, the
  // data, control and ready drivers each own their documented signal group.
  initial begin
    vif.rst_ni = 1'b0;

    vif.operands_i = '0;
    vif.rnd_mode_i = fpnew_pkg::RNE;
    vif.op_i = fpnew_pkg::FMADD;
    vif.op_mod_i = 1'b0;
    vif.is_boxed_i = '0;

    vif.tag_i = '0;
    vif.mask_i = 1'b0;
    vif.aux_i = '0;

    vif.in_valid_i = 1'b0;

    vif.flush_i = 1'b0;

    vif.out_ready_i = 1'b1;
    
    vif.reg_ena_i = '0;
  end

  initial begin
    uvm_config_db#(virtual fma_if)::set(null, "*", "vif", vif);
    run_test();
  end

  initial begin
    #10ms;
    $fatal(1, "Global FMA UVM timeout");
  end
endmodule


interface fma_if (input logic clk_i);
  import fpnew_pkg::*;
  import fma_config_pkg::*;

  logic                             rst_ni;

  logic [2:0][FMA_WIDTH-1:0]        operands_i;
  logic [2:0]                       is_boxed_i;
  fpnew_pkg::roundmode_e            rnd_mode_i;
  fpnew_pkg::operation_e            op_i;
  logic                             op_mod_i;
  fma_tag_t                         tag_i;
  logic                             mask_i;
  fma_aux_t                         aux_i;
  logic                             in_valid_i;
  logic                             in_ready_o;
  logic                             flush_i;

  fma_word_t                        result_o;
  fpnew_pkg::status_t               status_o;
  logic                             extension_bit_o;
  fma_tag_t                         tag_o;
  logic                             mask_o;
  fma_aux_t                         aux_o;
  logic                             out_valid_o;
  logic                             out_ready_i;
  logic                             busy_o;
  // The testbench top selects the DUT's elaborated ExtRegEnaWidth slice. The
  // verification environment never drives an external register override.
  logic [31:0]                      reg_ena_i;
  logic                             early_out_valid_o;

  clocking data_drv_cb @(negedge clk_i);
    default input #1step output #0;
    output operands_i, is_boxed_i, rnd_mode_i, op_i, op_mod_i;
    output tag_i, mask_i, aux_i, in_valid_i;
    input  rst_ni, flush_i, in_ready_o;
  endclocking

  clocking control_drv_cb @(negedge clk_i);
    default input #1step output #0;
    output rst_ni, flush_i;
  endclocking

  clocking ready_drv_cb @(negedge clk_i);
    default input #1step output #0;
    output out_ready_i;
    input  rst_ni, flush_i;
  endclocking

  clocking mon_cb @(posedge clk_i);
    default input #1step;
    input rst_ni;
    input operands_i, is_boxed_i, rnd_mode_i, op_i, op_mod_i;
    input tag_i, mask_i, aux_i, in_valid_i, in_ready_o, flush_i;
    input result_o, status_o, extension_bit_o, tag_o, mask_o, aux_o;
    input out_valid_o, out_ready_i, busy_o, early_out_valid_o;
  endclocking
endinterface


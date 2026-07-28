// SPDX-License-Identifier: SHL-0.51

module fma_protocol_checker (fma_if vif);
  import fma_config_pkg::*;

  localparam int unsigned EXP_BITS = (FMA_WIDTH == 16) ? 5 :
                                     (FMA_WIDTH == 32) ? 8 : 11;
  localparam int unsigned MAN_BITS = FMA_WIDTH - EXP_BITS - 1;
  localparam logic [FMA_WIDTH-1:0] CANONICAL_QNAN =
    {1'b0, {EXP_BITS{1'b1}}, 1'b1, {(MAN_BITS-1){1'b0}}};

  property p_input_stable_when_stalled;
    @(posedge vif.clk_i) disable iff (!vif.rst_ni || vif.flush_i)
      vif.in_valid_i && !vif.in_ready_o
      |=> vif.in_valid_i &&
          $stable({vif.operands_i, vif.is_boxed_i, vif.rnd_mode_i,
                   vif.op_i, vif.op_mod_i, vif.tag_i, vif.mask_i, vif.aux_i});
  endproperty
  a_input_stable_when_stalled: assert property (p_input_stable_when_stalled);

  property p_output_stable_when_stalled;
    @(posedge vif.clk_i) disable iff (!vif.rst_ni || vif.flush_i)
      vif.out_valid_o && !vif.out_ready_i
      |=> vif.out_valid_o &&
          $stable({vif.result_o, vif.status_o, vif.extension_bit_o,
                   vif.tag_o, vif.mask_o, vif.aux_o});
  endproperty
  a_output_stable_when_stalled: assert property (p_output_stable_when_stalled);

  a_valid_output_known: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o |->
        !$isunknown({vif.result_o, vif.status_o, vif.extension_bit_o,
                     vif.tag_o, vif.mask_o, vif.aux_o}));

  a_extension_bit_is_one: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o |-> (vif.extension_bit_o === 1'b1));

  // The FMA can produce only: no flags, NX, UF+NX, OF+NX, or NV.
  a_status_is_legal: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o |->
        (vif.status_o inside {5'b00000, 5'b00001, 5'b00011,
                              5'b00101, 5'b10000}));

  a_nv_returns_canonical_qnan: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o && vif.status_o.NV |->
        (vif.result_o == CANONICAL_QNAN));

  a_divide_by_zero_never_set: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o |-> !vif.status_o.DZ);

  a_underflow_implies_inexact: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o && vif.status_o.UF |-> vif.status_o.NX);

  a_overflow_implies_inexact: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o && vif.status_o.OF |-> vif.status_o.NX);

  a_nv_excludes_other_flags: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o && vif.status_o.NV |->
        !(vif.status_o.DZ || vif.status_o.OF ||
          vif.status_o.UF || vif.status_o.NX));

  a_overflow_underflow_exclusive: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o |-> !(vif.status_o.OF && vif.status_o.UF));

  a_input_valid_implies_busy: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.in_valid_i |-> vif.busy_o);

  a_output_valid_implies_busy: assert property (
    @(posedge vif.clk_i) disable iff (!vif.rst_ni)
      vif.out_valid_o |-> vif.busy_o);
endmodule

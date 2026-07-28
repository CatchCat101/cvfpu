// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_INITIAL_RESET_SEQUENCE_SVH
`define FMA_INITIAL_RESET_SEQUENCE_SVH

class fma_initial_reset_sequence extends fma_control_base_sequence;
  `uvm_object_utils(fma_initial_reset_sequence)

  int unsigned reset_cycles = 5;

  function new(string name = "fma_initial_reset_sequence");
    super.new(name);
  endfunction

  virtual task body();
    send_state(1'b0, 1'b0, reset_cycles);
    send_state(1'b1, 1'b0, 1);
  endtask
endclass

`endif

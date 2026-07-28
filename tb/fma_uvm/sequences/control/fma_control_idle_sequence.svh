// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_IDLE_SEQUENCE_SVH
`define FMA_CONTROL_IDLE_SEQUENCE_SVH

class fma_control_idle_sequence extends fma_control_base_sequence;
  `uvm_object_utils(fma_control_idle_sequence)

  int unsigned cycles = 1;

  function new(string name = "fma_control_idle_sequence");
    super.new(name);
  endfunction

  virtual task body();
    send_state(1'b1, 1'b0, cycles);
  endtask
endclass

`endif

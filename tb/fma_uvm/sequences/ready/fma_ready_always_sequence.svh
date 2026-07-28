// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_READY_ALWAYS_SEQUENCE_SVH
`define FMA_READY_ALWAYS_SEQUENCE_SVH

class fma_ready_always_sequence extends fma_ready_base_sequence;
  `uvm_object_utils(fma_ready_always_sequence)

  int unsigned cycles = 1;

  function new(string name = "fma_ready_always_sequence");
    super.new(name);
  endfunction

  virtual task body();
    send_segment(1'b1, cycles);
  endtask
endclass

`endif

// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_BASE_SEQUENCE_SVH
`define FMA_CONTROL_BASE_SEQUENCE_SVH

class fma_control_base_sequence extends uvm_sequence #(fma_control_item);
  `uvm_object_utils(fma_control_base_sequence)
  `uvm_declare_p_sequencer(fma_control_sequencer)

  function new(string name = "fma_control_base_sequence");
    super.new(name);
  endfunction

  virtual task send_state(bit rst_ni, bit flush_i, int unsigned cycles = 1);
    fma_control_item item;
    item = fma_control_item::type_id::create("control_item");
    item.rst_ni  = rst_ni;
    item.flush_i = flush_i;
    item.cycles  = (cycles == 0) ? 1 : cycles;
    start_item(item);
    finish_item(item);
  endtask

  virtual task body();
  endtask
endclass

`endif

// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_READY_BASE_SEQUENCE_SVH
`define FMA_READY_BASE_SEQUENCE_SVH

class fma_ready_base_sequence extends uvm_sequence #(fma_ready_item);
  `uvm_object_utils(fma_ready_base_sequence)
  `uvm_declare_p_sequencer(fma_ready_sequencer)

  function new(string name = "fma_ready_base_sequence");
    super.new(name);
  endfunction

  virtual task send_segment(bit ready, int unsigned cycles = 1);
    fma_ready_item item;
    item = fma_ready_item::type_id::create("ready_item");
    item.ready  = ready;
    item.cycles = (cycles == 0) ? 1 : cycles;
    start_item(item);
    finish_item(item);
  endtask

  virtual task body();
  endtask
endclass

`endif

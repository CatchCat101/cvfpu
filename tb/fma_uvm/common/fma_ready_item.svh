// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_READY_ITEM_SVH
`define FMA_READY_ITEM_SVH

class fma_ready_item extends uvm_sequence_item;
  rand bit          ready;
  rand int unsigned cycles;

  constraint positive_run_length_c { cycles > 0; }

  `uvm_object_utils_begin(fma_ready_item)
    `uvm_field_int(ready, UVM_DEFAULT)
    `uvm_field_int(cycles, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_ready_item");
    super.new(name);
  endfunction
endclass

`endif


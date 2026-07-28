// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_ITEM_SVH
`define FMA_CONTROL_ITEM_SVH

class fma_control_item extends uvm_sequence_item;
  rand bit          rst_ni;
  rand bit          flush_i;
  rand int unsigned cycles;

  constraint positive_run_length_c { cycles > 0; }

  `uvm_object_utils_begin(fma_control_item)
    `uvm_field_int(rst_ni, UVM_DEFAULT)
    `uvm_field_int(flush_i, UVM_DEFAULT)
    `uvm_field_int(cycles, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_control_item");
    super.new(name);
  endfunction
endclass

`endif


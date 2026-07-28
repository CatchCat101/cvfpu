// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_EVENT_SVH
`define FMA_CONTROL_EVENT_SVH

class fma_control_event extends uvm_sequence_item;
  fma_control_event_kind_e kind;
  logic in_valid;
  logic in_ready;
  logic out_valid;
  logic out_ready;
  logic busy;

  `uvm_object_utils_begin(fma_control_event)
    `uvm_field_enum(fma_control_event_kind_e, kind, UVM_DEFAULT)
    `uvm_field_int(in_valid, UVM_DEFAULT)
    `uvm_field_int(in_ready, UVM_DEFAULT)
    `uvm_field_int(out_valid, UVM_DEFAULT)
    `uvm_field_int(out_ready, UVM_DEFAULT)
    `uvm_field_int(busy, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_control_event");
    super.new(name);
  endfunction
endclass

`endif


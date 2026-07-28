// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CHECKED_RECORD_SVH
`define FMA_CHECKED_RECORD_SVH

class fma_checked_record extends uvm_sequence_item;
  fma_input_context   input_context;
  fma_word_t          result;
  fpnew_pkg::status_t status;
  logic               extension_bit;
  fma_tag_t           tag;
  logic               mask;
  fma_aux_t           aux;

  `uvm_object_utils_begin(fma_checked_record)
    `uvm_field_object(input_context, UVM_DEFAULT)
    `uvm_field_int(result, UVM_DEFAULT)
    `uvm_field_int(status, UVM_DEFAULT)
    `uvm_field_int(extension_bit, UVM_DEFAULT)
    `uvm_field_int(tag, UVM_DEFAULT)
    `uvm_field_int(mask, UVM_DEFAULT)
    `uvm_field_int(aux, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_checked_record");
    super.new(name);
  endfunction
endclass

`endif

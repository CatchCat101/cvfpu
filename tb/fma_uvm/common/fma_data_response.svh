// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_DATA_RESPONSE_SVH
`define FMA_DATA_RESPONSE_SVH

class fma_data_response extends uvm_sequence_item;
  fma_data_completion_e completion = FMA_DATA_ACCEPTED;

  `uvm_object_utils_begin(fma_data_response)
    `uvm_field_enum(fma_data_completion_e, completion, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_data_response");
    super.new(name);
  endfunction
endclass

`endif


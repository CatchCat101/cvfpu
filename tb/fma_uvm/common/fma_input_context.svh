// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_INPUT_CONTEXT_SVH
`define FMA_INPUT_CONTEXT_SVH

class fma_input_context extends uvm_sequence_item;
  fma_word_t             operands[3];
  logic [2:0]            is_boxed;
  fpnew_pkg::roundmode_e rnd_mode;
  fpnew_pkg::operation_e op_i;
  logic                  op_mod_i;
  fma_tag_t              tag;
  logic                  mask;
  fma_aux_t              aux;

  `uvm_object_utils_begin(fma_input_context)
    `uvm_field_sarray_int(operands, UVM_DEFAULT)
    `uvm_field_int(is_boxed, UVM_DEFAULT)
    `uvm_field_enum(fpnew_pkg::roundmode_e, rnd_mode, UVM_DEFAULT)
    `uvm_field_enum(fpnew_pkg::operation_e, op_i, UVM_DEFAULT)
    `uvm_field_int(op_mod_i, UVM_DEFAULT)
    `uvm_field_int(tag, UVM_DEFAULT)
    `uvm_field_int(mask, UVM_DEFAULT)
    `uvm_field_int(aux, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_input_context");
    super.new(name);
  endfunction

  function fma_function_e function_kind();
    return decode_fma_function(op_i, op_mod_i);
  endfunction

  function string convert2string();
    return $sformatf(
      "op=%s mod=%0b rm=%s A=%h B=%h C=%h boxed=%03b tag=%02h mask=%0b aux=%02h",
      op_i.name(), op_mod_i, rnd_mode.name(), operands[0], operands[1], operands[2],
      is_boxed, tag, mask, aux
    );
  endfunction
endclass

`endif


// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_OPERATION_ITEM_SVH
`define FMA_OPERATION_ITEM_SVH

class fma_operation_item extends uvm_sequence_item;
  rand fma_word_t              operands[3];
  rand logic [2:0]             is_boxed;
  rand fpnew_pkg::roundmode_e  rnd_mode;
  rand fpnew_pkg::operation_e  op_i;
  rand logic                   op_mod_i;
  rand fma_tag_t               tag;
  rand logic                   mask;
  rand fma_aux_t               aux;

  fma_data_completion_e completion = FMA_DATA_ACCEPTED;

  constraint supported_rounding_mode_c {
    rnd_mode inside {
      fpnew_pkg::RNE, fpnew_pkg::RTZ, fpnew_pkg::RDN,
      fpnew_pkg::RUP, fpnew_pkg::RMM
    };
  }

  constraint supported_raw_operation_c {
    op_i inside {
      fpnew_pkg::FMADD, fpnew_pkg::FNMSUB, fpnew_pkg::ADD,
      fpnew_pkg::ADDS, fpnew_pkg::MUL
    };
  }

  `uvm_object_utils_begin(fma_operation_item)
    `uvm_field_sarray_int(operands, UVM_DEFAULT)
    `uvm_field_int(is_boxed, UVM_DEFAULT)
    `uvm_field_enum(fpnew_pkg::roundmode_e, rnd_mode, UVM_DEFAULT)
    `uvm_field_enum(fpnew_pkg::operation_e, op_i, UVM_DEFAULT)
    `uvm_field_int(op_mod_i, UVM_DEFAULT)
    `uvm_field_int(tag, UVM_DEFAULT)
    `uvm_field_int(mask, UVM_DEFAULT)
    `uvm_field_int(aux, UVM_DEFAULT)
    `uvm_field_enum(fma_data_completion_e, completion, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_operation_item");
    super.new(name);
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


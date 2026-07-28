// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_VIRTUAL_BASE_SEQUENCE_SVH
`define FMA_VIRTUAL_BASE_SEQUENCE_SVH

class fma_virtual_base_sequence extends uvm_sequence #(uvm_sequence_item);
  `uvm_object_utils(fma_virtual_base_sequence)
  `uvm_declare_p_sequencer(fma_virtual_sequencer)

  function new(string name = "fma_virtual_base_sequence");
    super.new(name);
  endfunction

  virtual task initial_reset();
    fma_initial_reset_sequence reset_sequence;
    reset_sequence = fma_initial_reset_sequence::type_id::create("initial_reset_sequence");
    reset_sequence.start(p_sequencer.control_sequencer);
  endtask

  virtual task leave_safe_controls();
    fma_control_idle_sequence control_stop;
    fma_ready_always_sequence ready_stop;
    control_stop = fma_control_idle_sequence::type_id::create("control_stop");
    ready_stop   = fma_ready_always_sequence::type_id::create("ready_stop");
    control_stop.cycles = 1;
    ready_stop.cycles   = 1;
    control_stop.start(p_sequencer.control_sequencer);
    ready_stop.start(p_sequencer.ready_sequencer);
  endtask

  virtual function fma_operation_item make_function_item(
    int unsigned function_index,
    int unsigned serial,
    bit mul_modifier = 0
  );
    fma_operation_item item;
    item = fma_operation_item::type_id::create($sformatf("function_item_%0d", serial));
    item.op_i        = fma_operand_utils::function_operation(function_index);
    item.op_mod_i    = fma_operand_utils::function_modifier(function_index, mul_modifier);
    item.rnd_mode    = fpnew_pkg::RNE;
    item.operands[0] = fma_operand_utils::one();
    item.operands[1] = fma_operand_utils::two();
    item.operands[2] = fma_operand_utils::one();
    item.is_boxed    = 3'b111;
    item.tag         = serial;
    item.mask        = serial[0];
    item.aux         = serial ^ 8'h5a;
    return item;
  endfunction

  virtual function fma_operation_item make_raw_item(
    int unsigned raw_index,
    fpnew_pkg::roundmode_e rnd_mode,
    int unsigned serial
  );
    fma_operation_item item;
    item = fma_operation_item::type_id::create($sformatf("raw_item_%0d", serial));
    item.op_i        = fma_operand_utils::raw_operation(raw_index);
    item.op_mod_i    = fma_operand_utils::raw_modifier(raw_index);
    item.rnd_mode    = rnd_mode;
    item.operands[0] = fma_operand_utils::one();
    item.operands[1] = fma_operand_utils::two();
    item.operands[2] = fma_operand_utils::min_normal();
    item.is_boxed    = 3'b111;
    item.tag         = serial;
    item.mask        = serial[0];
    item.aux         = serial ^ 8'ha5;
    return item;
  endfunction

endclass

`endif

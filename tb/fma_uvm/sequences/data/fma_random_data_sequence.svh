// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_RANDOM_DATA_SEQUENCE_SVH
`define FMA_RANDOM_DATA_SEQUENCE_SVH

class fma_random_data_sequence extends fma_data_base_sequence;
  `uvm_object_utils(fma_random_data_sequence)

  int unsigned num_items = 1000;
  int unsigned max_gap_cycles = 3;
  bit continuous = 0;

  function new(string name = "fma_random_data_sequence");
    super.new(name);
  endfunction

  virtual function fma_operation_item random_operation(int unsigned index);
    fma_operation_item item;
    int unsigned raw_index;
    item = fma_operation_item::type_id::create($sformatf("random_item_%0d", index));
    raw_index = $urandom_range(9, 0);
    item.op_i         = fma_operand_utils::raw_operation(raw_index);
    item.op_mod_i     = fma_operand_utils::raw_modifier(raw_index);
    item.rnd_mode     = fma_operand_utils::random_roundmode();
    foreach (item.operands[i])
      item.operands[i] = fma_operand_utils::mixed_random_value();
    item.is_boxed = $urandom_range(7, 0);
    item.tag      = $urandom();
    item.mask     = $urandom_range(1, 0);
    item.aux      = $urandom();
    return item;
  endfunction

  virtual task body();
    for (int unsigned i = 0; i < num_items; i++) begin
      int unsigned gap;
      gap = continuous ? 0 : $urandom_range(max_gap_cycles, 0);
      send_operation(random_operation(i), gap);
    end
  endtask
endclass

`endif

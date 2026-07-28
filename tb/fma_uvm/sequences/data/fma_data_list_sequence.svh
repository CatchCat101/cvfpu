// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_DATA_LIST_SEQUENCE_SVH
`define FMA_DATA_LIST_SEQUENCE_SVH

class fma_data_list_sequence extends fma_data_base_sequence;
  `uvm_object_utils(fma_data_list_sequence)

  fma_operation_item operations[$];
  int unsigned gaps[$];

  function new(string name = "fma_data_list_sequence");
    super.new(name);
  endfunction

  function void add(fma_operation_item item, int unsigned gap_cycles = 0);
    operations.push_back(item);
    gaps.push_back(gap_cycles);
  endfunction

  virtual task body();
    foreach (operations[i])
      send_operation(operations[i], gaps[i]);
  endtask
endclass

`endif

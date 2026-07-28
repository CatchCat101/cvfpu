// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_RANDOM_DATA_TEST_SVH
`define FMA_RANDOM_DATA_TEST_SVH

class fma_random_data_test extends fma_base_test;
  `uvm_component_utils(fma_random_data_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function fma_virtual_base_sequence create_virtual_sequence();
    return fma_random_data_virtual_sequence::type_id::create("sequence");
  endfunction
endclass

`endif

// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_DATA_SEQUENCER_SVH
`define FMA_DATA_SEQUENCER_SVH

class fma_data_sequencer extends uvm_sequencer #(fma_operation_item, fma_data_response);
  `uvm_component_utils(fma_data_sequencer)

  virtual fma_if vif;

  function new(string name = "fma_data_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

`endif


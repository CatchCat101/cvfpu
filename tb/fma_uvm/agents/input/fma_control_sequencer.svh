// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_SEQUENCER_SVH
`define FMA_CONTROL_SEQUENCER_SVH

class fma_control_sequencer extends uvm_sequencer #(fma_control_item);
  `uvm_component_utils(fma_control_sequencer)

  virtual fma_if vif;

  function new(string name = "fma_control_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

`endif


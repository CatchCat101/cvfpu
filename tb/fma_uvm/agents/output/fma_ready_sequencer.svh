// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_READY_SEQUENCER_SVH
`define FMA_READY_SEQUENCER_SVH

class fma_ready_sequencer extends uvm_sequencer #(fma_ready_item);
  `uvm_component_utils(fma_ready_sequencer)

  virtual fma_if vif;

  function new(string name = "fma_ready_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass

`endif


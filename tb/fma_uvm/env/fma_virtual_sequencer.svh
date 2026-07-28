// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_VIRTUAL_SEQUENCER_SVH
`define FMA_VIRTUAL_SEQUENCER_SVH

class fma_virtual_sequencer extends uvm_sequencer #(uvm_sequence_item);
  `uvm_component_utils(fma_virtual_sequencer)

  fma_data_sequencer    data_sequencer;
  fma_control_sequencer control_sequencer;
  fma_ready_sequencer   ready_sequencer;

  // Sequences may observe the interface to coordinate phases, but all signal
  // driving remains in the three leaf drivers.
  virtual fma_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass

`endif

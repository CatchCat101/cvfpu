// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_RANDOM_CONTROL_VIRTUAL_SEQUENCE_SVH
`define FMA_RANDOM_CONTROL_VIRTUAL_SEQUENCE_SVH

class fma_random_control_virtual_sequence extends fma_virtual_base_sequence;
  `uvm_object_utils(fma_random_control_virtual_sequence)

  int unsigned num_items = 10000;

  function new(string name = "fma_random_control_virtual_sequence");
    super.new(name);
  endfunction

  virtual task body();
    fma_random_data_sequence data_sequence;
    fma_random_ready_sequence ready_sequence;
    fma_random_control_sequence control_sequence;
    void'($value$plusargs("NB_TXNS=%d", num_items));
    initial_reset();
    data_sequence    = fma_random_data_sequence::type_id::create("data_sequence");
    ready_sequence   = fma_random_ready_sequence::type_id::create("ready_sequence");
    control_sequence = fma_random_control_sequence::type_id::create("control_sequence");
    data_sequence.num_items         = num_items;
    data_sequence.max_gap_cycles    = 2;
    ready_sequence.total_cycles     = num_items * 3 + 32;
    ready_sequence.max_low_cycles   = 16;
    control_sequence.total_cycles   = num_items * 3 + 32;
    fork
      data_sequence.start(p_sequencer.data_sequencer);
      ready_sequence.start(p_sequencer.ready_sequencer);
      control_sequence.start(p_sequencer.control_sequencer);
    join
    leave_safe_controls();
  endtask
endclass

`endif

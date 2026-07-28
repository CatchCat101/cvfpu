// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_FLOW_CONTROL_VIRTUAL_SEQUENCE_SVH
`define FMA_FLOW_CONTROL_VIRTUAL_SEQUENCE_SVH

class fma_flow_control_virtual_sequence extends fma_virtual_base_sequence;
  `uvm_object_utils(fma_flow_control_virtual_sequence)

  function new(string name = "fma_flow_control_virtual_sequence");
    super.new(name);
  endfunction

  virtual task body();
    fma_data_list_sequence data_sequence;
    fma_ready_pattern_sequence ready_sequence;
    int unsigned serial;

    initial_reset();
    data_sequence  = fma_data_list_sequence::type_id::create("data_sequence");
    ready_sequence = fma_ready_pattern_sequence::type_id::create("ready_sequence");

    // Start with one accepted operation followed by an intentional input bubble.
    // Together with the first ready-low segment below, this creates the state
    // "terminal pipeline stage valid, preceding stage empty, output blocked".
    // That state is required to check early_out_valid_o independently of a full
    // pipeline; continuous traffic alone would mask an incorrect ready index.
    // The remaining region is continuous (including NumPipeRegs=0 same-edge
    // flow), followed by deterministic bubbles and enough traffic to fill the
    // pipeline.
    for (int i = 0; i < 160; i++) begin
      fma_operation_item item;
      item = make_raw_item(i % 10, fma_operand_utils::random_roundmode(), serial++);
      data_sequence.add(item,
                        (i == 1) ? 4 :
                        ((i < 48) ? 0 : ((i % 9) == 0 ? 3 : (i % 4 == 0))));
    end

    ready_sequence.add(1, 1);
    ready_sequence.add(0, 4);
    ready_sequence.add(1, 8);
    ready_sequence.add(0, 1);
    ready_sequence.add(1, 4);
    ready_sequence.add(0, 5);
    ready_sequence.add(1, 3);
    ready_sequence.add(0, 16);
    ready_sequence.add(1, 12);
    ready_sequence.add(0, 2);
    ready_sequence.add(1, 1);

    fork
      data_sequence.start(p_sequencer.data_sequencer);
      ready_sequence.start(p_sequencer.ready_sequencer);
    join
    leave_safe_controls();
  endtask
endclass

`endif

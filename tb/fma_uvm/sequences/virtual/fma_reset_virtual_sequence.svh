// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_RESET_VIRTUAL_SEQUENCE_SVH
`define FMA_RESET_VIRTUAL_SEQUENCE_SVH

class fma_reset_virtual_sequence extends fma_virtual_base_sequence;
  `uvm_object_utils(fma_reset_virtual_sequence)

  function new(string name = "fma_reset_virtual_sequence");
    super.new(name);
  endfunction

  virtual task body();
    fma_data_list_sequence traffic;
    fma_data_list_sequence recovery;
    fma_control_pattern_sequence controls;
    fma_ready_pattern_sequence ready_sequence;
    int unsigned serial;

    initial_reset();
    traffic        = fma_data_list_sequence::type_id::create("traffic");
    recovery       = fma_data_list_sequence::type_id::create("recovery");
    controls       = fma_control_pattern_sequence::type_id::create("controls");
    ready_sequence = fma_ready_pattern_sequence::type_id::create("ready_sequence");

    for (int i = 0; i < 180; i++)
      traffic.add(make_raw_item(i % 10, fma_operand_utils::random_roundmode(), serial++),
                  (i % 17) == 0);

    // Resets occur while idle, while traffic is accepted, and while output is
    // blocked. One reset also overlaps flush to check reset priority.
    controls.add(1, 0, 3);
    controls.add(0, 0, 2);
    controls.add(1, 0, 8);
    controls.add(0, 0, 3);
    controls.add(1, 0, 12);
    controls.add(0, 1, 2);
    controls.add(1, 0, 10);
    controls.add(0, 0, 2);
    controls.add(1, 0, 24);

    ready_sequence.add(1, 6);
    ready_sequence.add(0, 12);
    ready_sequence.add(1, 4);
    ready_sequence.add(0, 16);
    ready_sequence.add(1, 1);

    fork
      traffic.start(p_sequencer.data_sequencer);
      controls.start(p_sequencer.control_sequencer);
      ready_sequence.start(p_sequencer.ready_sequencer);
    join

    begin
      fma_ready_always_sequence ready_final;
      fma_control_idle_sequence control_final;
      ready_final   = fma_ready_always_sequence::type_id::create("ready_final");
      control_final = fma_control_idle_sequence::type_id::create("control_final");
      control_final.start(p_sequencer.control_sequencer);
      ready_final.start(p_sequencer.ready_sequencer);
    end
    recovery.add(make_function_item(0, serial++));
    recovery.add(make_function_item(4, serial++));
    recovery.start(p_sequencer.data_sequencer);
    leave_safe_controls();
  endtask
endclass

`endif

// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_FLUSH_VIRTUAL_SEQUENCE_SVH
`define FMA_FLUSH_VIRTUAL_SEQUENCE_SVH

class fma_flush_virtual_sequence extends fma_virtual_base_sequence;
  `uvm_object_utils(fma_flush_virtual_sequence)

  function new(string name = "fma_flush_virtual_sequence");
    super.new(name);
  endfunction

  protected task drive_control_state(bit rst_ni, bit flush_i,
                                      int unsigned cycles = 1);
    fma_control_pattern_sequence control_sequence;
    control_sequence = fma_control_pattern_sequence::type_id::create(
      "flush_control_state");
    control_sequence.add(rst_ni, flush_i, cycles);
    control_sequence.start(p_sequencer.control_sequencer);
  endtask

  protected task wait_for_input_handshake();
    repeat (200) begin
      @(posedge p_sequencer.vif.clk_i);
      if (p_sequencer.vif.rst_ni && !p_sequencer.vif.flush_i &&
          p_sequencer.vif.in_valid_i && p_sequencer.vif.in_ready_o)
        return;
    end
    `uvm_fatal("FLUSH_SCENARIO", "Timed out waiting for an input handshake")
  endtask

  protected task wait_for_blocked_output();
    repeat (200) begin
      @(posedge p_sequencer.vif.clk_i);
      if (p_sequencer.vif.rst_ni && !p_sequencer.vif.flush_i &&
          p_sequencer.vif.out_valid_o && !p_sequencer.vif.out_ready_i)
        return;
    end
    `uvm_fatal("FLUSH_SCENARIO", "Timed out waiting for a blocked output")
  endtask

  protected task wait_for_output_handshake();
    repeat (200) begin
      @(posedge p_sequencer.vif.clk_i);
      if (p_sequencer.vif.rst_ni && !p_sequencer.vif.flush_i &&
          p_sequencer.vif.out_valid_o && p_sequencer.vif.out_ready_i)
        return;
    end
    `uvm_fatal("FLUSH_SCENARIO", "Timed out waiting for an output handshake")
  endtask

  protected task run_occupied_flush_scenarios();
    // Continuous traffic keeps the input active on the cycle after the
    // observed handshake. The one-cycle pulse therefore deterministically
    // overlaps an apparent input handshake at the interface.
    wait_for_input_handshake();
    drive_control_state(1, 1, 1);
    drive_control_state(1, 0, 2);

    // A blocked output remains valid, so this two-cycle flush is guaranteed to
    // clear an occupied pipeline while output ready is low.
    wait_for_blocked_output();
    drive_control_state(1, 1, 2);
    drive_control_state(1, 0, 2);

    // After ready returns high, overlap a three-cycle flush with an apparent
    // output handshake and verify that the transfer is canceled.
    wait_for_output_handshake();
    drive_control_state(1, 1, 3);
    drive_control_state(1, 0, 24);
  endtask

  virtual task body();
    fma_data_list_sequence traffic;
    fma_data_list_sequence recovery;
    fma_ready_pattern_sequence ready_sequence;
    int unsigned serial;

    initial_reset();
    traffic        = fma_data_list_sequence::type_id::create("traffic");
    recovery       = fma_data_list_sequence::type_id::create("recovery");
    ready_sequence = fma_ready_pattern_sequence::type_id::create("ready_sequence");

    for (int i = 0; i < 180; i++)
      traffic.add(make_raw_item(i % 10, fma_operand_utils::random_roundmode(), serial++),
                  (i % 13) == 0);

    // Generate a true idle flush before either traffic sequence starts.
    drive_control_state(1, 1, 1);
    drive_control_state(1, 0, 2);

    // Alternating ready produces both a visible output handshake and a blocked
    // valid around the scheduled flush pulses.
    ready_sequence.add(1, 7);
    ready_sequence.add(0, 9);
    ready_sequence.add(1, 6);
    ready_sequence.add(0, 16);
    ready_sequence.add(1, 1);

    fork
      traffic.start(p_sequencer.data_sequencer);
      ready_sequence.start(p_sequencer.ready_sequencer);
      run_occupied_flush_scenarios();
    join

    // A known finite sentinel proves that both input and output flow recover.
    recovery.add(make_function_item(0, serial++));
    recovery.add(make_function_item(6, serial++, 1));
    begin
      fma_ready_always_sequence ready_final;
      fma_control_idle_sequence control_final;
      ready_final   = fma_ready_always_sequence::type_id::create("ready_final");
      control_final = fma_control_idle_sequence::type_id::create("control_final");
      control_final.start(p_sequencer.control_sequencer);
      ready_final.start(p_sequencer.ready_sequencer);
    end
    recovery.start(p_sequencer.data_sequencer);
    leave_safe_controls();
  endtask
endclass

`endif

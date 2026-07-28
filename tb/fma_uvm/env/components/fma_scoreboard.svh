// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_SCOREBOARD_SVH
`define FMA_SCOREBOARD_SVH

class fma_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(fma_scoreboard)

  uvm_analysis_imp_scb_expected #(fma_expected_record, fma_scoreboard)
    scb_expected_imp;
  uvm_analysis_imp_scb_actual #(fma_actual_record, fma_scoreboard)
    scb_actual_imp;
  uvm_analysis_imp_scb_control #(fma_control_event, fma_scoreboard)
    scb_control_imp;
  uvm_analysis_port #(fma_checked_record) scb_checked_data_ap;

  fma_expected_record expected_q[$];
  fma_actual_record   actual_q[$];
  time                actual_arrival_q[$];

  int unsigned pass_count;
  int unsigned mismatch_count;
  int unsigned unexpected_actual_count;

  protected event actual_deferred_event;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    scb_expected_imp       = new("scb_expected_imp", this);
    scb_actual_imp         = new("scb_actual_imp", this);
    scb_control_imp        = new("scb_control_imp", this);
    scb_checked_data_ap    = new("scb_checked_data_ap", this);
  endfunction

  function automatic fma_expected_record clone_expected(fma_expected_record src);
    fma_expected_record copy;
    if ((src == null) || !$cast(copy, src.clone()))
      `uvm_fatal("SCB_CLONE", "Failed to clone expected record")
    return copy;
  endfunction

  function automatic fma_actual_record clone_actual(fma_actual_record src);
    fma_actual_record copy;
    if ((src == null) || !$cast(copy, src.clone()))
      `uvm_fatal("SCB_CLONE", "Failed to clone actual record")
    return copy;
  endfunction

  function automatic fma_input_context clone_context(fma_input_context src);
    fma_input_context copy;
    if ((src == null) || !$cast(copy, src.clone()))
      `uvm_fatal("SCB_CLONE", "Failed to clone input context")
    return copy;
  endfunction

  function void write_scb_expected(fma_expected_record t);
    expected_q.push_back(clone_expected(t));
    compare_available();
  endfunction

  function void write_scb_actual(fma_actual_record t);
    actual_q.push_back(clone_actual(t));
    actual_arrival_q.push_back($time);
    compare_available();
    if (actual_q.size() != 0)
      -> actual_deferred_event;
  endfunction

  function void write_scb_control(fma_control_event t);
    if (t == null)
      `uvm_fatal("SCB_NULL", "Scoreboard received a null control event")

    case (t.kind)
      FMA_RESET_ASSERT, FMA_FLUSH: clear_pending(t.kind.name());
      FMA_RESET_DEASSERT: ;
      default:
        `uvm_error("SCB_CTRL", $sformatf("Unknown control event kind %0d", t.kind))
    endcase
  endfunction

  protected function void clear_pending(string reason);
    if ((expected_q.size() != 0) || (actual_q.size() != 0))
      `uvm_info("SCB_CLEAR", $sformatf(
        "%s cleared %0d expected and %0d actual records",
        reason, expected_q.size(), actual_q.size()), UVM_MEDIUM)
    expected_q.delete();
    actual_q.delete();
    actual_arrival_q.delete();
  endfunction

  protected function void compare_available();
    fma_expected_record expected;
    fma_actual_record   actual;

    while ((expected_q.size() != 0) && (actual_q.size() != 0)) begin
      expected = expected_q.pop_front();
      actual   = actual_q.pop_front();
      void'(actual_arrival_q.pop_front());
      compare_one(expected, actual);
    end
  endfunction

  protected function void compare_one(
    fma_expected_record expected,
    fma_actual_record   actual
  );
    bit                match;
    fma_checked_record checked;

    match = (actual.result        === expected.result)        &&
            (actual.status        === expected.status)        &&
            (actual.extension_bit === expected.extension_bit) &&
            (actual.tag           === expected.tag)           &&
            (actual.mask          === expected.mask)          &&
            (actual.aux           === expected.aux);

    if (!match) begin
      mismatch_count++;
      `uvm_error("FMA_MISMATCH", $sformatf(
        {"FMA mismatch\n",
         "  expected result=0x%0h status=%05b ext=%0b tag=0x%0h mask=%0b aux=0x%0h\n",
         "  actual   result=0x%0h status=%05b ext=%0b tag=0x%0h mask=%0b aux=0x%0h"},
        expected.result, expected.status, expected.extension_bit,
        expected.tag, expected.mask, expected.aux,
        actual.result, actual.status, actual.extension_bit,
        actual.tag, actual.mask, actual.aux))
      return;
    end

    pass_count++;
    checked = fma_checked_record::type_id::create("checked");
    checked.input_context = clone_context(expected.input_context);
    checked.result        = actual.result;
    checked.status        = actual.status;
    checked.extension_bit = actual.extension_bit;
    checked.tag           = actual.tag;
    checked.mask          = actual.mask;
    checked.aux           = actual.aux;
    scb_checked_data_ap.write(checked);
  endfunction

  // UVM analysis callbacks are functions and therefore cannot contain #0.
  // This process delays rejection by one delta cycle so a zero-register DUT's
  // output-monitor callback may legally precede the input/reference callback
  // at the same simulation time.  A later-cycle expected record is never used.
  task run_phase(uvm_phase phase);
    forever begin
      @actual_deferred_event;
      #0;
      expire_unmatched_actuals();
    end
  endtask

  protected function void expire_unmatched_actuals();
    int index = 0;
    compare_available();
    while (index < actual_q.size()) begin
      if (actual_arrival_q[index] <= $time) begin
        unexpected_actual_count++;
        `uvm_error("UNEXPECTED_ACTUAL", $sformatf(
          "Output handshake at time %0t has no accepted input at the same or an earlier time",
          actual_arrival_q[index]))
        actual_q.delete(index);
        actual_arrival_q.delete(index);
      end else begin
        index++;
      end
    end
  endfunction

  function bit is_idle();
    return (expected_q.size() == 0) && (actual_q.size() == 0);
  endfunction

  function int unsigned pending_count();
    return expected_q.size() + actual_q.size();
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (expected_q.size() != 0)
      `uvm_error("SCB_PENDING", $sformatf(
        "%0d expected FMA results were not observed", expected_q.size()))
    if (actual_q.size() != 0)
      `uvm_error("SCB_PENDING", $sformatf(
        "%0d actual FMA results remain unpaired", actual_q.size()))
    if (mismatch_count != 0)
      `uvm_error("SCB_FAILED", $sformatf(
        "Scoreboard observed %0d mismatches", mismatch_count))
    if (unexpected_actual_count != 0)
      `uvm_error("SCB_FAILED", $sformatf(
        "Scoreboard observed %0d unexpected outputs", unexpected_actual_count))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", $sformatf(
      "checked=%0d mismatches=%0d unexpected_outputs=%0d pending=%0d",
      pass_count, mismatch_count, unexpected_actual_count, pending_count()), UVM_LOW)
  endfunction
endclass

`endif

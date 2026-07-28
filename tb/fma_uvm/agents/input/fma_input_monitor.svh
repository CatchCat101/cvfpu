// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_INPUT_MONITOR_SVH
`define FMA_INPUT_MONITOR_SVH

class fma_input_monitor extends uvm_monitor;
  `uvm_component_utils(fma_input_monitor)

  fma_input_agent_cfg cfg;
  uvm_analysis_port #(fma_input_context) in_data_ap;
  uvm_analysis_port #(fma_control_event) in_control_ap;

  function new(string name = "fma_input_monitor", uvm_component parent = null);
    super.new(name, parent);
    in_data_ap = new("in_data_ap", this);
    in_control_ap = new("in_control_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fma_input_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("FMA_INPUT_CFG", "fma_input_agent_cfg was not configured")
    end
    if (cfg.vif == null) begin
      `uvm_fatal("FMA_INPUT_VIF", "fma_input_agent_cfg.vif is null")
    end
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_clocked_inputs_and_flush();
      monitor_reset_assertions();
      monitor_reset_deassertions();
    join
  endtask

  task monitor_clocked_inputs_and_flush();
    fma_input_context input_context;
    fma_control_event control_event;

    forever begin
      @(cfg.vif.mon_cb);
      if (cfg.vif.mon_cb.rst_ni !== 1'b1) begin
        continue;
      end

      if (cfg.vif.mon_cb.flush_i === 1'b1) begin
        control_event = fma_control_event::type_id::create("flush_event");
        control_event.kind = FMA_FLUSH;
        sample_clocked_flow_state(control_event);
        in_control_ap.write(control_event);
      end

      if ((cfg.vif.mon_cb.flush_i === 1'b0) &&
          (cfg.vif.mon_cb.in_valid_i === 1'b1) &&
          (cfg.vif.mon_cb.in_ready_o === 1'b1)) begin
        input_context = fma_input_context::type_id::create("input_context");
        for (int unsigned i = 0; i < 3; i++) begin
          input_context.operands[i] = cfg.vif.mon_cb.operands_i[i];
        end
        input_context.is_boxed = cfg.vif.mon_cb.is_boxed_i;
        input_context.rnd_mode = cfg.vif.mon_cb.rnd_mode_i;
        input_context.op_i = cfg.vif.mon_cb.op_i;
        input_context.op_mod_i = cfg.vif.mon_cb.op_mod_i;
        input_context.tag = cfg.vif.mon_cb.tag_i;
        input_context.mask = cfg.vif.mon_cb.mask_i;
        input_context.aux = cfg.vif.mon_cb.aux_i;
        in_data_ap.write(input_context);
      end
    end
  endtask

  task monitor_reset_assertions();
    fma_control_event control_event;
    forever begin
      @(negedge cfg.vif.rst_ni);
      control_event = fma_control_event::type_id::create("reset_assert_event");
      control_event.kind = FMA_RESET_ASSERT;
      sample_async_flow_state(control_event);
      in_control_ap.write(control_event);
    end
  endtask

  task monitor_reset_deassertions();
    fma_control_event control_event;
    forever begin
      @(posedge cfg.vif.rst_ni);
      control_event = fma_control_event::type_id::create("reset_deassert_event");
      control_event.kind = FMA_RESET_DEASSERT;
      sample_async_flow_state(control_event);
      in_control_ap.write(control_event);
    end
  endtask

  // A synchronous flush event describes the interface state sampled at that
  // rising edge, before the DUT's sequential flush updates become visible.
  function void sample_clocked_flow_state(fma_control_event control_event);
    control_event.in_valid = cfg.vif.mon_cb.in_valid_i;
    control_event.in_ready = cfg.vif.mon_cb.in_ready_o;
    control_event.out_valid = cfg.vif.mon_cb.out_valid_o;
    control_event.out_ready = cfg.vif.mon_cb.out_ready_i;
    control_event.busy = cfg.vif.mon_cb.busy_o;
  endfunction

  // Reset assertion/deassertion is asynchronous and has no associated sampled
  // clocking-block edge, so those events use the live interface values.
  function void sample_async_flow_state(fma_control_event control_event);
    control_event.in_valid = cfg.vif.in_valid_i;
    control_event.in_ready = cfg.vif.in_ready_o;
    control_event.out_valid = cfg.vif.out_valid_o;
    control_event.out_ready = cfg.vif.out_ready_i;
    control_event.busy = cfg.vif.busy_o;
  endfunction
endclass

`endif

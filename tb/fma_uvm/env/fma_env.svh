// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_ENV_SVH
`define FMA_ENV_SVH

class fma_env extends uvm_env;
  `uvm_component_utils(fma_env)

  fma_env_cfg cfg;

  fma_input_agent_cfg  input_cfg;
  fma_output_agent_cfg output_cfg;

  fma_input_agent       input_agent;
  fma_output_agent      output_agent;
  fma_reference_model   reference_model;
  fma_scoreboard        scoreboard;
  fma_coverage          coverage;
  fma_virtual_sequencer virtual_sequencer;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fma_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("ENV_CFG", "fma_env_cfg was not configured")
    if (cfg.vif == null)
      `uvm_fatal("ENV_VIF", "fma_env_cfg.vif is null")

    input_cfg = fma_input_agent_cfg::type_id::create("input_cfg");
    input_cfg.vif       = cfg.vif;
    input_cfg.is_active = cfg.input_is_active;
    output_cfg = fma_output_agent_cfg::type_id::create("output_cfg");
    output_cfg.vif       = cfg.vif;
    output_cfg.is_active = cfg.output_is_active;

    uvm_config_db#(fma_input_agent_cfg)::set(
      this, "input_agent", "cfg", input_cfg);
    uvm_config_db#(fma_output_agent_cfg)::set(
      this, "output_agent", "cfg", output_cfg);

    input_agent       = fma_input_agent::type_id::create("input_agent", this);
    output_agent      = fma_output_agent::type_id::create("output_agent", this);
    reference_model   = fma_reference_model::type_id::create("reference_model", this);
    scoreboard        = fma_scoreboard::type_id::create("scoreboard", this);
    coverage          = fma_coverage::type_id::create("coverage", this);
    virtual_sequencer = fma_virtual_sequencer::type_id::create(
      "virtual_sequencer", this);
    virtual_sequencer.vif = cfg.vif;
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    input_agent.input_monitor.in_data_ap.connect(
      reference_model.analysis_export);
    input_agent.input_monitor.in_data_ap.connect(
      coverage.in_agt_data_imp);
    reference_model.ref_expected_ap.connect(scoreboard.scb_expected_imp);
    output_agent.output_monitor.out_agt_data_ap.connect(
      scoreboard.scb_actual_imp);

    // Control is sent directly to both consumers.  The scoreboard does not
    // re-publish a derived control summary.
    input_agent.input_monitor.in_control_ap.connect(
      scoreboard.scb_control_imp);
    input_agent.input_monitor.in_control_ap.connect(
      coverage.in_agt_control_imp);

    // Result coverage is sampled only after a successful comparison.
    scoreboard.scb_checked_data_ap.connect(coverage.scb_checked_data_imp);

    virtual_sequencer.data_sequencer    = input_agent.data_sequencer;
    virtual_sequencer.control_sequencer = input_agent.control_sequencer;
    virtual_sequencer.ready_sequencer   = output_agent.ready_sequencer;
  endfunction

  // Wait until the scoreboarding queues and the interface stay empty for a
  // pipeline-dependent number of complete cycles.  Tests call this after data
  // and control sequences have stopped and out_ready_i has been restored high.
  task wait_for_idle();
    int unsigned cycles;
    int unsigned stable_cycles;
    int unsigned required_stable_cycles;

    cycles                 = 0;
    stable_cycles          = 0;
    required_stable_cycles = cfg.num_pipe_regs + 2;
    while ((stable_cycles < required_stable_cycles) &&
           (cycles < cfg.drain_timeout_cycles)) begin
      @(posedge cfg.vif.clk_i);
      cycles++;
      if ((cfg.vif.rst_ni === 1'b1) &&
          (cfg.vif.flush_i === 1'b0) &&
          (cfg.vif.busy_o === 1'b0) &&
          (cfg.vif.out_valid_o === 1'b0) &&
          scoreboard.is_idle()) begin
        stable_cycles++;
      end else begin
        stable_cycles = 0;
      end
    end

    if (stable_cycles < required_stable_cycles)
      `uvm_fatal("DRAIN_TIMEOUT", $sformatf(
        {"FMA environment did not drain within %0d cycles: ",
         "busy=%0b out_valid=%0b scoreboard_pending=%0d"},
        cfg.drain_timeout_cycles, cfg.vif.busy_o, cfg.vif.out_valid_o,
        scoreboard.pending_count()))
  endtask
endclass

`endif

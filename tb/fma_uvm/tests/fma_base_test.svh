// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_BASE_TEST_SVH
`define FMA_BASE_TEST_SVH

`ifndef FMA_NUM_PIPE_REGS
  `define FMA_NUM_PIPE_REGS 0
`endif
`ifndef FMA_PIPE_CONFIG
  `define FMA_PIPE_CONFIG 0
`endif

class fma_base_test extends uvm_test;
  fma_env     env;
  fma_env_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function fma_virtual_base_sequence create_virtual_sequence();
    `uvm_fatal("NO_VSEQ", "concrete test did not select a virtual sequence")
    return null;
  endfunction

  virtual function void build_phase(uvm_phase phase);
    virtual fma_if vif;
    super.build_phase(phase);
    if (!uvm_config_db#(fma_env_cfg)::get(this, "", "env_cfg", cfg))
      cfg = fma_env_cfg::type_id::create("cfg");
    if (cfg.vif == null) begin
      if (!uvm_config_db#(virtual fma_if)::get(this, "", "vif", vif))
        `uvm_fatal("NOVIF", "fma_if was not configured")
      cfg.vif = vif;
    end
    cfg.num_pipe_regs = `FMA_NUM_PIPE_REGS;
    cfg.pipe_config = fpnew_pkg::pipe_config_t'(`FMA_PIPE_CONFIG);
    void'($value$plusargs("DRAIN_TIMEOUT=%d", cfg.drain_timeout_cycles));
    uvm_config_db#(fma_env_cfg)::set(this, "env", "cfg", cfg);
    env = fma_env::type_id::create("env", this);
  endfunction

  virtual task wait_for_clean_drain();
    int unsigned stable_cycles;
    int unsigned elapsed_cycles;
    int unsigned required_cycles;
    stable_cycles   = 0;
    elapsed_cycles  = 0;
    required_cycles = cfg.num_pipe_regs + 2;
    if (required_cycles < 2) required_cycles = 2;

    while ((stable_cycles < required_cycles) &&
           (elapsed_cycles < cfg.drain_timeout_cycles)) begin
      @(posedge cfg.vif.clk_i);
      elapsed_cycles++;
      if (cfg.vif.rst_ni && !cfg.vif.flush_i &&
          !cfg.vif.busy_o && !cfg.vif.out_valid_o &&
          env.scoreboard.is_idle() && (env.scoreboard.pending_count() == 0))
        stable_cycles++;
      else
        stable_cycles = 0;
    end
    if (stable_cycles < required_cycles)
      `uvm_fatal("DRAIN_TIMEOUT",
        $sformatf("not idle after %0d cycles: busy=%0b out_valid=%0b pending=%0d",
                  elapsed_cycles, cfg.vif.busy_o, cfg.vif.out_valid_o,
                  env.scoreboard.pending_count()))
  endtask

  virtual task run_phase(uvm_phase phase);
    fma_virtual_base_sequence vseq;
    phase.raise_objection(this);
    vseq = create_virtual_sequence();
    vseq.start(env.virtual_sequencer);
    wait_for_clean_drain();
    phase.drop_objection(this);
  endtask
endclass

`endif

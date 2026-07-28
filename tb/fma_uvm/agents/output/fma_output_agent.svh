// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_OUTPUT_AGENT_SVH
`define FMA_OUTPUT_AGENT_SVH

class fma_output_agent extends uvm_agent;
  `uvm_component_utils(fma_output_agent)

  fma_output_agent_cfg cfg;
  fma_ready_sequencer  ready_sequencer;
  fma_ready_driver     ready_driver;
  fma_output_monitor   output_monitor;

  function new(string name = "fma_output_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fma_output_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("FMA_OUTPUT_CFG", "fma_output_agent_cfg was not configured")
    end
    if (cfg.vif == null) begin
      `uvm_fatal("FMA_OUTPUT_VIF", "fma_output_agent_cfg.vif is null")
    end

    uvm_config_db#(fma_output_agent_cfg)::set(this, "*", "cfg", cfg);
    output_monitor = fma_output_monitor::type_id::create("output_monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      ready_sequencer = fma_ready_sequencer::type_id::create("ready_sequencer", this);
      ready_driver = fma_ready_driver::type_id::create("ready_driver", this);
      ready_sequencer.vif = cfg.vif;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      ready_driver.seq_item_port.connect(ready_sequencer.seq_item_export);
    end
  endfunction
endclass

`endif


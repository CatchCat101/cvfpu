// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_INPUT_AGENT_SVH
`define FMA_INPUT_AGENT_SVH

class fma_input_agent extends uvm_agent;
  `uvm_component_utils(fma_input_agent)

  fma_input_agent_cfg  cfg;
  fma_data_sequencer   data_sequencer;
  fma_data_driver      data_driver;
  fma_control_sequencer control_sequencer;
  fma_control_driver   control_driver;
  fma_input_monitor    input_monitor;

  function new(string name = "fma_input_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fma_input_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("FMA_INPUT_CFG", "fma_input_agent_cfg was not configured")
    end
    if (cfg.vif == null) begin
      `uvm_fatal("FMA_INPUT_VIF", "fma_input_agent_cfg.vif is null")
    end

    uvm_config_db#(fma_input_agent_cfg)::set(this, "*", "cfg", cfg);
    input_monitor = fma_input_monitor::type_id::create("input_monitor", this);

    if (cfg.is_active == UVM_ACTIVE) begin
      data_sequencer = fma_data_sequencer::type_id::create("data_sequencer", this);
      data_driver = fma_data_driver::type_id::create("data_driver", this);
      control_sequencer = fma_control_sequencer::type_id::create("control_sequencer", this);
      control_driver = fma_control_driver::type_id::create("control_driver", this);
      data_sequencer.vif = cfg.vif;
      control_sequencer.vif = cfg.vif;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (cfg.is_active == UVM_ACTIVE) begin
      data_driver.seq_item_port.connect(data_sequencer.seq_item_export);
      control_driver.seq_item_port.connect(control_sequencer.seq_item_export);
    end
  endfunction
endclass

`endif


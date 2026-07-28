// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_DRIVER_SVH
`define FMA_CONTROL_DRIVER_SVH

class fma_control_driver extends uvm_driver #(fma_control_item);
  `uvm_component_utils(fma_control_driver)

  fma_input_agent_cfg cfg;

  function new(string name = "fma_control_driver", uvm_component parent = null);
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
  endfunction

  task run_phase(uvm_phase phase);
    fma_control_item req;

    // The top initializes reset low before UVM starts. This driver owns both
    // control pins from here onward and leaves reset asserted until directed
    // by the initial reset sequence.
    cfg.vif.rst_ni <= 1'b0;
    cfg.vif.flush_i <= 1'b0;

    forever begin
      seq_item_port.get_next_item(req);
      @(cfg.vif.control_drv_cb);
      cfg.vif.control_drv_cb.rst_ni <= req.rst_ni;
      cfg.vif.control_drv_cb.flush_i <= req.flush_i;
      repeat (req.cycles) @(posedge cfg.vif.clk_i);
      seq_item_port.item_done();
    end
  endtask
endclass

`endif


// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_READY_DRIVER_SVH
`define FMA_READY_DRIVER_SVH

class fma_ready_driver extends uvm_driver #(fma_ready_item);
  `uvm_component_utils(fma_ready_driver)

  fma_output_agent_cfg cfg;

  function new(string name = "fma_ready_driver", uvm_component parent = null);
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
  endfunction

  task run_phase(uvm_phase phase);
    fma_ready_item req;

    // Ready is permissive before the first segment and after the final one.
    cfg.vif.out_ready_i <= 1'b1;

    forever begin
      @(cfg.vif.ready_drv_cb);
      req = null;
      seq_item_port.try_next_item(req);
      if (req == null) begin
        cfg.vif.ready_drv_cb.out_ready_i <= 1'b1;
        continue;
      end

      cfg.vif.ready_drv_cb.out_ready_i <= req.ready;
      repeat (req.cycles) @(posedge cfg.vif.clk_i);
      seq_item_port.item_done();
    end
  endtask
endclass

`endif


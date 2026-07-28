// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_OUTPUT_MONITOR_SVH
`define FMA_OUTPUT_MONITOR_SVH

class fma_output_monitor extends uvm_monitor;
  `uvm_component_utils(fma_output_monitor)

  fma_output_agent_cfg cfg;
  uvm_analysis_port #(fma_actual_record) out_agt_data_ap;

  function new(string name = "fma_output_monitor", uvm_component parent = null);
    super.new(name, parent);
    out_agt_data_ap = new("out_agt_data_ap", this);
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
    fma_actual_record actual;

    forever begin
      @(cfg.vif.mon_cb);
      if ((cfg.vif.mon_cb.rst_ni === 1'b1) &&
          (cfg.vif.mon_cb.flush_i === 1'b0) &&
          (cfg.vif.mon_cb.out_valid_o === 1'b1) &&
          (cfg.vif.mon_cb.out_ready_i === 1'b1)) begin
        actual = fma_actual_record::type_id::create("actual_record");
        actual.result = cfg.vif.mon_cb.result_o;
        actual.status = cfg.vif.mon_cb.status_o;
        actual.extension_bit = cfg.vif.mon_cb.extension_bit_o;
        actual.tag = cfg.vif.mon_cb.tag_o;
        actual.mask = cfg.vif.mon_cb.mask_o;
        actual.aux = cfg.vif.mon_cb.aux_o;
        out_agt_data_ap.write(actual);
      end
    end
  endtask
endclass

`endif


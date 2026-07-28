// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_INPUT_AGENT_CFG_SVH
`define FMA_INPUT_AGENT_CFG_SVH

class fma_input_agent_cfg extends uvm_object;
  virtual fma_if vif;
  uvm_active_passive_enum is_active = UVM_ACTIVE;

  `uvm_object_utils_begin(fma_input_agent_cfg)
    `uvm_field_enum(uvm_active_passive_enum, is_active, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "fma_input_agent_cfg");
    super.new(name);
  endfunction
endclass

`endif


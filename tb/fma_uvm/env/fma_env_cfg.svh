// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_ENV_CFG_SVH
`define FMA_ENV_CFG_SVH

class fma_env_cfg extends uvm_object;
  `uvm_object_utils(fma_env_cfg)

  virtual fma_if vif;

  uvm_active_passive_enum input_is_active  = UVM_ACTIVE;
  uvm_active_passive_enum output_is_active = UVM_ACTIVE;

  // These values mirror the elaborated DUT configuration.  Components use
  // them for drain/diagnostic policy only; they do not change the RTL.
  int unsigned             num_pipe_regs          = 0;
  fpnew_pkg::pipe_config_t pipe_config            = fpnew_pkg::BEFORE;
  int unsigned             drain_timeout_cycles   = 1000;
  int unsigned             max_ready_low_cycles   = 16;

  function new(string name = "fma_env_cfg");
    super.new(name);
  endfunction
endclass

`endif

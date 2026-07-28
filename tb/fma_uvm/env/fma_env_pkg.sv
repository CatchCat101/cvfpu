// SPDX-License-Identifier: SHL-0.51

package fma_env_pkg;
  import uvm_pkg::*;
  import fpnew_pkg::*;
  import fma_config_pkg::*;
  import fma_types_pkg::*;
  import fma_input_agent_pkg::*;
  import fma_output_agent_pkg::*;
  `include "uvm_macros.svh"

  `uvm_analysis_imp_decl(_scb_expected)
  `uvm_analysis_imp_decl(_scb_actual)
  `uvm_analysis_imp_decl(_scb_control)
  `uvm_analysis_imp_decl(_cov_input)
  `uvm_analysis_imp_decl(_cov_checked)
  `uvm_analysis_imp_decl(_cov_control)

  `include "fma_env_cfg.svh"
  `include "fma_virtual_sequencer.svh"
  `include "components/fma_reference_model.svh"
  `include "components/fma_scoreboard.svh"
  `include "components/fma_coverage.svh"
  `include "fma_env.svh"
endpackage

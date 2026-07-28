// SPDX-License-Identifier: SHL-0.51

package fma_test_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import fpnew_pkg::*;
  import fma_config_pkg::*;
  import fma_types_pkg::*;
  import fma_input_agent_pkg::*;
  import fma_output_agent_pkg::*;
  import fma_env_pkg::*;
  import fma_seq_pkg::*;

  `include "fma_base_test.svh"
  `include "fma_smoke_test.svh"
  `include "fma_directed_test.svh"
  `include "fma_flow_control_test.svh"
  `include "fma_flush_test.svh"
  `include "fma_reset_test.svh"
  `include "fma_random_data_test.svh"
  `include "fma_random_control_test.svh"
endpackage

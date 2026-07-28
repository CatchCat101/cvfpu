// SPDX-License-Identifier: SHL-0.51

package fma_seq_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"

  import fpnew_pkg::*;
  import fma_config_pkg::*;
  import fma_types_pkg::*;
  import fma_input_agent_pkg::*;
  import fma_output_agent_pkg::*;
  import fma_env_pkg::*;

  `include "fma_operand_utils.svh"
  `include "fma_data_base_sequence.svh"
  `include "fma_data_list_sequence.svh"
  `include "fma_random_data_sequence.svh"

  `include "fma_control_base_sequence.svh"
  `include "fma_initial_reset_sequence.svh"
  `include "fma_control_pattern_sequence.svh"
  `include "fma_control_idle_sequence.svh"
  `include "fma_random_control_sequence.svh"

  `include "fma_ready_base_sequence.svh"
  `include "fma_ready_always_sequence.svh"
  `include "fma_ready_pattern_sequence.svh"
  `include "fma_random_ready_sequence.svh"

  `include "fma_virtual_base_sequence.svh"
  `include "fma_smoke_virtual_sequence.svh"
  `include "fma_directed_virtual_sequence.svh"
  `include "fma_flow_control_virtual_sequence.svh"
  `include "fma_flush_virtual_sequence.svh"
  `include "fma_reset_virtual_sequence.svh"
  `include "fma_random_data_virtual_sequence.svh"
  `include "fma_random_control_virtual_sequence.svh"
endpackage

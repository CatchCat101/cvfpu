// SPDX-License-Identifier: SHL-0.51

package fma_types_pkg;
  import uvm_pkg::*;
  import fpnew_pkg::*;
  import fma_config_pkg::*;
  `include "uvm_macros.svh"

  typedef enum int unsigned {
    FMA_FUNC_FMADD  = 0,
    FMA_FUNC_FMSUB  = 1,
    FMA_FUNC_FNMSUB = 2,
    FMA_FUNC_FNMADD = 3,
    FMA_FUNC_ADD    = 4,
    FMA_FUNC_SUB    = 5,
    FMA_FUNC_MUL    = 6
  } fma_function_e;

  typedef enum int unsigned {
    FMA_DATA_ACCEPTED,
    FMA_DATA_CANCELED_BY_RESET,
    FMA_DATA_CANCELED_BY_FLUSH
  } fma_data_completion_e;

  typedef enum int unsigned {
    FMA_RESET_ASSERT,
    FMA_RESET_DEASSERT,
    FMA_FLUSH
  } fma_control_event_kind_e;

  function automatic bit is_valid_raw_operation(fpnew_pkg::operation_e op);
    return op inside {
      fpnew_pkg::FMADD, fpnew_pkg::FNMSUB, fpnew_pkg::ADD,
      fpnew_pkg::ADDS, fpnew_pkg::MUL
    };
  endfunction

  function automatic fma_function_e decode_fma_function(
    fpnew_pkg::operation_e op,
    bit                    op_mod
  );
    case (op)
      fpnew_pkg::FMADD:  return op_mod ? FMA_FUNC_FMSUB  : FMA_FUNC_FMADD;
      fpnew_pkg::FNMSUB: return op_mod ? FMA_FUNC_FNMADD : FMA_FUNC_FNMSUB;
      fpnew_pkg::ADD,
      fpnew_pkg::ADDS:   return op_mod ? FMA_FUNC_SUB    : FMA_FUNC_ADD;
      fpnew_pkg::MUL:    return FMA_FUNC_MUL;
      default:           return FMA_FUNC_FMADD;
    endcase
  endfunction

  `include "fma_operation_item.svh"
  `include "fma_data_response.svh"
  `include "fma_input_context.svh"
  `include "fma_expected_record.svh"
  `include "fma_actual_record.svh"
  `include "fma_checked_record.svh"
  `include "fma_control_event.svh"
  `include "fma_ready_item.svh"
  `include "fma_control_item.svh"
endpackage

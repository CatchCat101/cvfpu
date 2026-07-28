// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_COVERAGE_SVH
`define FMA_COVERAGE_SVH

class fma_coverage extends uvm_component;
  `uvm_component_utils(fma_coverage)

  localparam int unsigned EXP_BITS = fpnew_pkg::exp_bits(FMA_FORMAT);
  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FMA_FORMAT);

  // fma_status_kind values.  Their numeric values are used in covergroups to
  // keep cross-bin declarations accepted consistently by simulators.
  localparam int unsigned STATUS_NO_FLAGS = 0;
  localparam int unsigned STATUS_NX_ONLY  = 1;
  localparam int unsigned STATUS_UF_NX    = 2;
  localparam int unsigned STATUS_OF_NX    = 3;
  localparam int unsigned STATUS_NV       = 4;
  localparam int unsigned STATUS_INVALID  = 5;

  localparam int unsigned RES_POS_ZERO       = 0;
  localparam int unsigned RES_NEG_ZERO       = 1;
  localparam int unsigned RES_POS_MIN_SUB    = 2;
  localparam int unsigned RES_NEG_MIN_SUB    = 3;
  localparam int unsigned RES_POS_MID_SUB    = 4;
  localparam int unsigned RES_NEG_MID_SUB    = 5;
  localparam int unsigned RES_POS_MAX_SUB    = 6;
  localparam int unsigned RES_NEG_MAX_SUB    = 7;
  localparam int unsigned RES_POS_MIN_NORMAL = 8;
  localparam int unsigned RES_NEG_MIN_NORMAL = 9;
  localparam int unsigned RES_POS_MID_NORMAL = 10;
  localparam int unsigned RES_NEG_MID_NORMAL = 11;
  localparam int unsigned RES_POS_MAX_FINITE = 12;
  localparam int unsigned RES_NEG_MAX_FINITE = 13;
  localparam int unsigned RES_POS_INFINITY   = 14;
  localparam int unsigned RES_NEG_INFINITY   = 15;
  localparam int unsigned RES_CANONICAL_QNAN = 16;
  localparam int unsigned RES_OTHER          = 17;

  uvm_analysis_imp_cov_input #(fma_input_context, fma_coverage)
    in_agt_data_imp;
  uvm_analysis_imp_cov_checked #(fma_checked_record, fma_coverage)
    scb_checked_data_imp;
  uvm_analysis_imp_cov_control #(fma_control_event, fma_coverage)
    in_agt_control_imp;

  // Sampled once for every accepted input handshake.  Raw operation coverage
  // deliberately keeps ADD and ADDS distinct while numerical-function
  // coverage combines them into ADD/SUB.
  covergroup input_cg with function sample(
    int unsigned raw_control,
    int unsigned function_code,
    int unsigned rounding_mode,
    int unsigned class_a,
    int unsigned class_b,
    int unsigned class_c,
    bit          boxed_a,
    bit          boxed_b,
    bit          boxed_c,
    int unsigned boxed_pattern,
    bit          mask
  );
    option.per_instance = 1;

    raw_control_cp: coverpoint raw_control {
      bins legal_raw_controls[] = {[0:9]};
      illegal_bins invalid = default;
    }
    function_cp: coverpoint function_code {
      bins numerical_functions[] = {[0:6]};
      illegal_bins invalid = default;
    }
    rounding_mode_cp: coverpoint rounding_mode {
      bins supported_modes[] = {[0:4]};
      illegal_bins unsupported = default;
    }
    class_a_cp: coverpoint class_a {
      bins sign_and_class[] = {[0:11]};
      illegal_bins invalid = default;
    }
    class_b_cp: coverpoint class_b {
      bins sign_and_class[] = {[0:11]};
      illegal_bins invalid = default;
    }
    class_c_cp: coverpoint class_c {
      bins sign_and_class[] = {[0:11]};
      illegal_bins invalid = default;
    }
    boxed_a_cp: coverpoint boxed_a;
    boxed_b_cp: coverpoint boxed_b;
    boxed_c_cp: coverpoint boxed_c;
    boxed_pattern_cp: coverpoint boxed_pattern {
      bins patterns[] = {[0:7]};
      illegal_bins invalid = default;
    }
    mask_cp: coverpoint mask;

    raw_control_rounding_cross: cross raw_control_cp, rounding_mode_cp;
    function_a_class_boxing_cross:
      cross function_cp, class_a_cp, boxed_a_cp;
    function_b_class_boxing_cross:
      cross function_cp, class_b_cp, boxed_b_cp;
    function_c_class_boxing_cross:
      cross function_cp, class_c_cp, boxed_c_cp;
    function_boxing_pattern_cross:
      cross function_cp, boxed_pattern_cp;
  endgroup

  // Sampled only after the scoreboard has compared a result successfully.
  // The 17 named result bins are selected boundary values, not a replacement
  // for arbitrary random-result checking.
  covergroup checked_result_cg with function sample(
    int unsigned function_code,
    int unsigned rounding_mode,
    int unsigned result_kind,
    int unsigned status_kind
  );
    option.per_instance = 1;

    function_cp: coverpoint function_code {
      bins numerical_functions[] = {[0:6]};
      illegal_bins invalid = default;
    }
    rounding_mode_cp: coverpoint rounding_mode {
      bins supported_modes[] = {[0:4]};
      illegal_bins unsupported = default;
    }
    result_kind_cp: coverpoint result_kind {
      bins pos_zero       = {RES_POS_ZERO};
      bins neg_zero       = {RES_NEG_ZERO};
      bins pos_min_sub    = {RES_POS_MIN_SUB};
      bins neg_min_sub    = {RES_NEG_MIN_SUB};
      bins pos_mid_sub    = {RES_POS_MID_SUB};
      bins neg_mid_sub    = {RES_NEG_MID_SUB};
      bins pos_max_sub    = {RES_POS_MAX_SUB};
      bins neg_max_sub    = {RES_NEG_MAX_SUB};
      bins pos_min_normal = {RES_POS_MIN_NORMAL};
      bins neg_min_normal = {RES_NEG_MIN_NORMAL};
      bins pos_mid_normal = {RES_POS_MID_NORMAL};
      bins neg_mid_normal = {RES_NEG_MID_NORMAL};
      bins pos_max_finite = {RES_POS_MAX_FINITE};
      bins neg_max_finite = {RES_NEG_MAX_FINITE};
      bins pos_infinity   = {RES_POS_INFINITY};
      bins neg_infinity   = {RES_NEG_INFINITY};
      bins canonical_qnan = {RES_CANONICAL_QNAN};
      bins other          = {RES_OTHER};
    }
    status_kind_cp: coverpoint status_kind {
      bins no_flags = {STATUS_NO_FLAGS};
      bins nx_only  = {STATUS_NX_ONLY};
      bins uf_nx    = {STATUS_UF_NX};
      bins of_nx    = {STATUS_OF_NX};
      bins nv       = {STATUS_NV};
      illegal_bins invalid = {STATUS_INVALID};
    }

    function_result_cross: cross function_cp, result_kind_cp {
      ignore_bins unselected_result =
        binsof(result_kind_cp) intersect {RES_OTHER};
    }

    function_status_cross: cross function_cp, status_kind_cp {
      // ADD and SUB cannot produce an underflow result in this FMA reuse mode.
      ignore_bins add_sub_uf_nx =
        binsof(function_cp) intersect {4, 5} &&
        binsof(status_kind_cp) intersect {STATUS_UF_NX};
    }

    rounding_exception_status_cross: cross rounding_mode_cp, status_kind_cp {
      ignore_bins no_exception_or_invalid =
        binsof(status_kind_cp) intersect {STATUS_NO_FLAGS, STATUS_NV};
    }

    result_status_cross: cross result_kind_cp, status_kind_cp {
      ignore_bins unselected_result =
        binsof(result_kind_cp) intersect {RES_OTHER};

      illegal_bins invalid_zero_or_subnormal =
        binsof(result_kind_cp) intersect {[RES_POS_ZERO:RES_NEG_MAX_SUB]} &&
        binsof(status_kind_cp) intersect
          {STATUS_NX_ONLY, STATUS_OF_NX, STATUS_NV};
      illegal_bins invalid_min_normal =
        binsof(result_kind_cp) intersect
          {RES_POS_MIN_NORMAL, RES_NEG_MIN_NORMAL} &&
        binsof(status_kind_cp) intersect {STATUS_OF_NX, STATUS_NV};
      illegal_bins invalid_mid_normal =
        binsof(result_kind_cp) intersect
          {RES_POS_MID_NORMAL, RES_NEG_MID_NORMAL} &&
        binsof(status_kind_cp) intersect
          {STATUS_UF_NX, STATUS_OF_NX, STATUS_NV};
      illegal_bins invalid_max_finite =
        binsof(result_kind_cp) intersect
          {RES_POS_MAX_FINITE, RES_NEG_MAX_FINITE} &&
        binsof(status_kind_cp) intersect {STATUS_UF_NX, STATUS_NV};
      illegal_bins invalid_infinity =
        binsof(result_kind_cp) intersect
          {RES_POS_INFINITY, RES_NEG_INFINITY} &&
        binsof(status_kind_cp) intersect
          {STATUS_NX_ONLY, STATUS_UF_NX, STATUS_NV};
      illegal_bins invalid_canonical_qnan =
        binsof(result_kind_cp) intersect {RES_CANONICAL_QNAN} &&
        binsof(status_kind_cp) intersect
          {STATUS_NX_ONLY, STATUS_UF_NX, STATUS_OF_NX};
    }
  endgroup

  // Control events are sampled directly from the input monitor.  Input and
  // output handshake states remain separate; intentionally no 3x3x2 cross is
  // created.  Continuous flush is represented by one sample per asserted edge.
  covergroup control_cg with function sample(
    int unsigned event_kind,
    int unsigned input_state,
    int unsigned output_state,
    bit          busy
  );
    option.per_instance = 1;

    event_cp: coverpoint event_kind {
      bins reset_assert   = {FMA_RESET_ASSERT};
      bins reset_deassert = {FMA_RESET_DEASSERT};
      bins flush          = {FMA_FLUSH};
      illegal_bins invalid = default;
    }
    flush_input_state_cp: coverpoint input_state iff (event_kind == FMA_FLUSH) {
      bins no_valid        = {0};
      bins valid_not_ready = {1};
      bins valid_and_ready = {2};
      illegal_bins invalid = default;
    }
    flush_output_state_cp: coverpoint output_state iff (event_kind == FMA_FLUSH) {
      bins no_valid        = {0};
      bins valid_not_ready = {1};
      bins valid_and_ready = {2};
      illegal_bins invalid = default;
    }
    flush_busy_cp: coverpoint busy iff (event_kind == FMA_FLUSH);
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_agt_data_imp       = new("in_agt_data_imp", this);
    scb_checked_data_imp  = new("scb_checked_data_imp", this);
    in_agt_control_imp    = new("in_agt_control_imp", this);
    input_cg              = new();
    checked_result_cg     = new();
    control_cg            = new();
  endfunction

  function automatic int unsigned decode_raw_control(
    fpnew_pkg::operation_e op_i,
    logic                  op_mod_i
  );
    unique case (op_i)
      fpnew_pkg::FMADD:  return 0 + int'(op_mod_i);
      fpnew_pkg::FNMSUB: return 2 + int'(op_mod_i);
      fpnew_pkg::ADD:    return 4 + int'(op_mod_i);
      fpnew_pkg::ADDS:   return 6 + int'(op_mod_i);
      fpnew_pkg::MUL:    return 8 + int'(op_mod_i);
      default:           return 10;
    endcase
  endfunction

  function automatic int unsigned decode_function(
    fpnew_pkg::operation_e op_i,
    logic                  op_mod_i
  );
    unique case (op_i)
      fpnew_pkg::FMADD:  return op_mod_i ? int'(FMA_FUNC_FMSUB)
                                         : int'(FMA_FUNC_FMADD);
      fpnew_pkg::FNMSUB: return op_mod_i ? int'(FMA_FUNC_FNMADD)
                                         : int'(FMA_FUNC_FNMSUB);
      fpnew_pkg::ADD,
      fpnew_pkg::ADDS:   return op_mod_i ? int'(FMA_FUNC_SUB)
                                         : int'(FMA_FUNC_ADD);
      fpnew_pkg::MUL:    return int'(FMA_FUNC_MUL);
      default:           return 7;
    endcase
  endfunction

  // Return one of 12 bins: positive zero/subnormal/normal/infinity/qNaN/sNaN,
  // followed by the six corresponding negative classes.  This classification
  // always uses the original payload, even when is_boxed is zero.
  function automatic int unsigned raw_operand_class(fma_word_t value);
    logic                    sign;
    logic [EXP_BITS-1:0]     exponent;
    logic [MAN_BITS-1:0]     fraction;
    int unsigned             magnitude_class;

    sign     = value[FMA_WIDTH-1];
    exponent = value[MAN_BITS +: EXP_BITS];
    fraction = value[MAN_BITS-1:0];

    if (exponent == '0)
      magnitude_class = (fraction == '0) ? 0 : 1;
    else if (exponent != '1)
      magnitude_class = 2;
    else if (fraction == '0)
      magnitude_class = 3;
    else
      magnitude_class = fraction[MAN_BITS-1] ? 4 : 5;

    return magnitude_class + (sign ? 6 : 0);
  endfunction

  function automatic int unsigned selected_result_kind(fma_word_t value);
    logic                    sign;
    logic [EXP_BITS-1:0]     exponent;
    logic [MAN_BITS-1:0]     fraction;
    logic [EXP_BITS-1:0]     middle_exponent;
    logic [EXP_BITS-1:0]     max_finite_exponent;
    logic [MAN_BITS-1:0]     middle_fraction;

    sign            = value[FMA_WIDTH-1];
    exponent        = value[MAN_BITS +: EXP_BITS];
    fraction        = value[MAN_BITS-1:0];
    middle_exponent = '0;
    max_finite_exponent = '1;
    middle_fraction = '0;
    middle_exponent[EXP_BITS-1] = 1'b1;
    max_finite_exponent = max_finite_exponent - 1'b1;
    middle_fraction[MAN_BITS-1] = 1'b1;

    if ((exponent == '0) && (fraction == '0))
      return sign ? RES_NEG_ZERO : RES_POS_ZERO;

    if (exponent == '0) begin
      if (fraction == {{(MAN_BITS-1){1'b0}}, 1'b1})
        return sign ? RES_NEG_MIN_SUB : RES_POS_MIN_SUB;
      if (fraction == middle_fraction)
        return sign ? RES_NEG_MID_SUB : RES_POS_MID_SUB;
      if (fraction == '1)
        return sign ? RES_NEG_MAX_SUB : RES_POS_MAX_SUB;
      return RES_OTHER;
    end

    if ((exponent == {{(EXP_BITS-1){1'b0}}, 1'b1}) && (fraction == '0))
      return sign ? RES_NEG_MIN_NORMAL : RES_POS_MIN_NORMAL;
    if ((exponent == middle_exponent) && (fraction == middle_fraction))
      return sign ? RES_NEG_MID_NORMAL : RES_POS_MID_NORMAL;
    if ((exponent == max_finite_exponent) && (fraction == '1))
      return sign ? RES_NEG_MAX_FINITE : RES_POS_MAX_FINITE;
    if ((exponent == '1) && (fraction == '0))
      return sign ? RES_NEG_INFINITY : RES_POS_INFINITY;
    if (!sign && (exponent == '1) &&
        (fraction == middle_fraction))
      return RES_CANONICAL_QNAN;
    return RES_OTHER;
  endfunction

  function automatic int unsigned classify_status(fpnew_pkg::status_t status);
    logic [4:0] status_bits;
    status_bits = {status.NV, status.DZ, status.OF, status.UF, status.NX};
    unique case (status_bits)
      5'b00000: return STATUS_NO_FLAGS;
      5'b00001: return STATUS_NX_ONLY;
      5'b00011: return STATUS_UF_NX;
      5'b00101: return STATUS_OF_NX;
      5'b10000: return STATUS_NV;
      default:  return STATUS_INVALID;
    endcase
  endfunction

  function automatic bit selected_result_status_is_legal(
    int unsigned result_kind,
    int unsigned status_kind
  );
    case (result_kind)
      RES_POS_ZERO, RES_NEG_ZERO,
      RES_POS_MIN_SUB, RES_NEG_MIN_SUB,
      RES_POS_MID_SUB, RES_NEG_MID_SUB,
      RES_POS_MAX_SUB, RES_NEG_MAX_SUB:
        return status_kind inside {STATUS_NO_FLAGS, STATUS_UF_NX};
      RES_POS_MIN_NORMAL, RES_NEG_MIN_NORMAL:
        return status_kind inside
          {STATUS_NO_FLAGS, STATUS_NX_ONLY, STATUS_UF_NX};
      RES_POS_MID_NORMAL, RES_NEG_MID_NORMAL:
        return status_kind inside {STATUS_NO_FLAGS, STATUS_NX_ONLY};
      RES_POS_MAX_FINITE, RES_NEG_MAX_FINITE:
        return status_kind inside
          {STATUS_NO_FLAGS, STATUS_NX_ONLY, STATUS_OF_NX};
      RES_POS_INFINITY, RES_NEG_INFINITY:
        return status_kind inside {STATUS_NO_FLAGS, STATUS_OF_NX};
      RES_CANONICAL_QNAN:
        return status_kind inside {STATUS_NO_FLAGS, STATUS_NV};
      default:
        return 1'b1;
    endcase
  endfunction

  function void write_cov_input(fma_input_context t);
    if (t == null)
      `uvm_fatal("COV_NULL", "Coverage received a null input context")
    input_cg.sample(
      decode_raw_control(t.op_i, t.op_mod_i),
      decode_function(t.op_i, t.op_mod_i),
      int'(t.rnd_mode),
      raw_operand_class(t.operands[0]),
      raw_operand_class(t.operands[1]),
      raw_operand_class(t.operands[2]),
      t.is_boxed[0], t.is_boxed[1], t.is_boxed[2],
      int'(t.is_boxed), t.mask
    );
  endfunction

  function void write_cov_checked(fma_checked_record t);
    int unsigned result_kind;
    int unsigned status_kind;
    if ((t == null) || (t.input_context == null))
      `uvm_fatal("COV_NULL", "Coverage received an incomplete checked record")

    result_kind = selected_result_kind(t.result);
    status_kind = classify_status(t.status);
    if (status_kind == STATUS_INVALID)
      `uvm_error("COV_STATUS", $sformatf(
        "Illegal FMA status combination %05b",
        {t.status.NV, t.status.DZ, t.status.OF, t.status.UF, t.status.NX}))
    if (!selected_result_status_is_legal(result_kind, status_kind))
      `uvm_error("COV_RESULT_STATUS", $sformatf(
        "Selected result kind %0d has illegal status kind %0d",
        result_kind, status_kind))

    checked_result_cg.sample(
      decode_function(t.input_context.op_i, t.input_context.op_mod_i),
      int'(t.input_context.rnd_mode), result_kind, status_kind
    );
  endfunction

  function void write_cov_control(fma_control_event t);
    int unsigned input_state;
    int unsigned output_state;
    if (t == null)
      `uvm_fatal("COV_NULL", "Coverage received a null control event")

    input_state  = !t.in_valid  ? 0 : (!t.in_ready  ? 1 : 2);
    output_state = !t.out_valid ? 0 : (!t.out_ready ? 1 : 2);
    control_cg.sample(int'(t.kind), input_state, output_state, t.busy);
  endfunction
endclass

`endif

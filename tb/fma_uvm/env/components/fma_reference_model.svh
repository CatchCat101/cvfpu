// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_REFERENCE_MODEL_SVH
`define FMA_REFERENCE_MODEL_SVH

import "DPI-C" function int fma_softfloat_eval(
  input  int unsigned     format,
  input  int unsigned     function_code,
  input  int unsigned     rounding_mode,
  input  longint unsigned operand_a,
  input  longint unsigned operand_b,
  input  longint unsigned operand_c,
  output longint unsigned result,
  output byte unsigned    status
);

class fma_reference_model extends uvm_subscriber #(fma_input_context);
  `uvm_component_utils(fma_reference_model)

  localparam int unsigned MAN_BITS = fpnew_pkg::man_bits(FMA_FORMAT);

  uvm_analysis_port #(fma_expected_record) ref_expected_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ref_expected_ap = new("ref_expected_ap", this);
  endfunction

  function automatic fma_function_e decode_function(
    fpnew_pkg::operation_e op_i,
    logic                  op_mod_i
  );
    unique case (op_i)
      fpnew_pkg::FMADD:
        return op_mod_i ? FMA_FUNC_FMSUB : FMA_FUNC_FMADD;
      fpnew_pkg::FNMSUB:
        return op_mod_i ? FMA_FUNC_FNMADD : FMA_FUNC_FNMSUB;
      fpnew_pkg::ADD,
      fpnew_pkg::ADDS:
        return op_mod_i ? FMA_FUNC_SUB : FMA_FUNC_ADD;
      fpnew_pkg::MUL:
        // Both raw modifier encodings intentionally exercise multiplication.
        return FMA_FUNC_MUL;
      default: begin
        `uvm_fatal("REF_OP", $sformatf("Unsupported FMA operation encoding %0d", op_i))
        return FMA_FUNC_FMADD;
      end
    endcase
  endfunction

  function automatic fma_word_t canonical_qnan();
    fma_word_t value = '0;
    value[FMA_WIDTH-2 -: fpnew_pkg::exp_bits(FMA_FORMAT)] = '1;
    value[MAN_BITS-1] = 1'b1;
    return value;
  endfunction

  function automatic longint unsigned widen(fma_word_t value);
    longint unsigned widened = '0;
    widened[FMA_WIDTH-1:0] = value;
    return widened;
  endfunction

  virtual function void write(fma_input_context t);
    fma_expected_record expected;
    fma_input_context   context_copy;
    fma_function_e      function_code;
    fma_word_t          a;
    fma_word_t          b;
    fma_word_t          c;
    longint unsigned    result64;
    byte unsigned       status8;
    int                 rc;

    if (t == null)
      `uvm_fatal("REF_NULL", "Reference model received a null input context")

    function_code = decode_function(t.op_i, t.op_mod_i);
    a = t.operands[0];
    b = t.operands[1];
    c = t.operands[2];

    // NaN boxing is checked only for operands used by the selected numerical
    // operation.  The DUT replaces A for ADD/ADDS and C for MUL, so invalid
    // boxing on those original, ignored operands must not influence the result.
    if (!(function_code inside {FMA_FUNC_ADD, FMA_FUNC_SUB}) && !t.is_boxed[0])
      a = canonical_qnan();
    if (!t.is_boxed[1])
      b = canonical_qnan();
    if ((function_code != FMA_FUNC_MUL) && !t.is_boxed[2])
      c = canonical_qnan();

    rc = fma_softfloat_eval(
      int'(FMA_FORMAT), int'(function_code), int'(t.rnd_mode),
      widen(a), widen(b), widen(c), result64, status8
    );
    if (rc != 0)
      `uvm_fatal("REF_DPI", $sformatf(
        "fma_softfloat_eval failed: rc=%0d format=%0d function=%0d rm=%0d",
        rc, FMA_FORMAT, function_code, t.rnd_mode))

    expected = fma_expected_record::type_id::create("expected");
    if (!$cast(context_copy, t.clone()))
      `uvm_fatal("REF_CLONE", "Failed to clone input context")
    expected.input_context = context_copy;
    expected.result        = fma_word_t'(result64[FMA_WIDTH-1:0]);
    expected.status        = fpnew_pkg::status_t'(status8[4:0]);
    expected.extension_bit = 1'b1;
    expected.tag           = t.tag;
    expected.mask          = t.mask;
    expected.aux           = t.aux;
    ref_expected_ap.write(expected);
  endfunction
endclass

`endif

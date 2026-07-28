// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_OPERAND_UTILS_SVH
`define FMA_OPERAND_UTILS_SVH

typedef enum int unsigned {
  FMA_POS_ZERO = 0,
  FMA_NEG_ZERO,
  FMA_POS_SUBNORMAL,
  FMA_NEG_SUBNORMAL,
  FMA_POS_NORMAL,
  FMA_NEG_NORMAL,
  FMA_POS_INFINITY,
  FMA_NEG_INFINITY,
  FMA_POS_QNAN,
  FMA_NEG_QNAN,
  FMA_POS_SNAN,
  FMA_NEG_SNAN
} fma_operand_class_e;

class fma_operand_utils;

  static function automatic int unsigned exp_bits();
    case (FMA_WIDTH)
      16: return 5;
      32: return 8;
      64: return 11;
      default: return 0;
    endcase
  endfunction

  static function automatic int unsigned man_bits();
    case (FMA_WIDTH)
      16: return 10;
      32: return 23;
      64: return 52;
      default: return 0;
    endcase
  endfunction

  static function automatic bit [63:0] width_mask();
    return (FMA_WIDTH == 64) ? 64'hffff_ffff_ffff_ffff
                             : ((64'h1 << FMA_WIDTH) - 1);
  endfunction

  static function automatic bit [63:0] fraction_mask();
    return (64'h1 << man_bits()) - 1;
  endfunction

  static function automatic bit [63:0] exponent_mask();
    return (64'h1 << exp_bits()) - 1;
  endfunction

  static function automatic fma_word_t random_word();
    bit [63:0] raw;
    raw = {$urandom(), $urandom()};
    return fma_word_t'(raw & width_mask());
  endfunction

  static function automatic fma_word_t from_fields(
    bit sign,
    bit [63:0] exponent,
    bit [63:0] fraction
  );
    bit [63:0] raw;
    raw = ((exponent & exponent_mask()) << man_bits()) |
          (fraction & fraction_mask());
    raw[FMA_WIDTH-1] = sign;
    return fma_word_t'(raw);
  endfunction

  // The class is selected first, then the remaining bits are randomized inside
  // that class.  This prevents normal values from overwhelming rare encodings.
  static function automatic fma_word_t value_of_class(fma_operand_class_e cls);
    bit sign;
    int unsigned kind;
    bit [63:0] exp;
    bit [63:0] frac;
    bit [63:0] frac_mask;
    bit [63:0] exp_mask;

    sign      = (int'(cls) & 1) != 0;
    kind      = int'(cls) >> 1;
    frac_mask = fraction_mask();
    exp_mask  = exponent_mask();
    frac      = {$urandom(), $urandom()} & frac_mask;

    case (kind)
      0: begin // zero
        exp  = 0;
        frac = 0;
      end
      1: begin // subnormal
        exp = 0;
        if (frac == 0) frac = 1;
      end
      2: begin // normal
        exp = 1 + ($urandom() % (exp_mask - 1));
      end
      3: begin // infinity
        exp  = exp_mask;
        frac = 0;
      end
      4: begin // quiet NaN
        exp  = exp_mask;
        frac = frac | (64'h1 << (man_bits() - 1));
      end
      default: begin // signaling NaN: quiet bit clear and payload nonzero
        exp  = exp_mask;
        frac = frac & ~(64'h1 << (man_bits() - 1));
        if (frac == 0) frac = 1;
      end
    endcase
    return from_fields(sign, exp, frac);
  endfunction

  static function automatic fma_word_t mixed_random_value();
    if ($urandom_range(1, 0) == 0)
      return random_word();
    return value_of_class(fma_operand_class_e'($urandom_range(11, 0)));
  endfunction

  static function automatic fma_word_t positive_zero();
    return from_fields(0, 0, 0);
  endfunction

  static function automatic fma_word_t negative_zero();
    return from_fields(1, 0, 0);
  endfunction

  static function automatic fma_word_t one();
    return from_fields(0, (64'h1 << (exp_bits() - 1)) - 1, 0);
  endfunction

  static function automatic fma_word_t two();
    return from_fields(0, (64'h1 << (exp_bits() - 1)), 0);
  endfunction

  static function automatic fma_word_t min_subnormal(bit sign = 0);
    return from_fields(sign, 0, 1);
  endfunction

  static function automatic fma_word_t middle_subnormal(bit sign = 0);
    return from_fields(sign, 0, 64'h1 << (man_bits() - 1));
  endfunction

  static function automatic fma_word_t max_subnormal(bit sign = 0);
    return from_fields(sign, 0, fraction_mask());
  endfunction

  static function automatic fma_word_t min_normal(bit sign = 0);
    return from_fields(sign, 1, 0);
  endfunction

  static function automatic fma_word_t middle_normal(bit sign = 0);
    return from_fields(sign, 64'h1 << (exp_bits() - 1),
                       64'h1 << (man_bits() - 1));
  endfunction

  // min_normal * this power of two equals exactly one half of min_subnormal.
  static function automatic fma_word_t half_min_subnormal_factor();
    bit [63:0] bias;
    bias = (64'h1 << (exp_bits() - 1)) - 1;
    return from_fields(0, bias - (man_bits() + 1), 0);
  endfunction

  static function automatic fma_word_t max_finite(bit sign = 0);
    return from_fields(sign, exponent_mask() - 1, fraction_mask());
  endfunction

  static function automatic fma_word_t infinity(bit sign = 0);
    return from_fields(sign, exponent_mask(), 0);
  endfunction

  static function automatic fma_word_t canonical_qnan();
    return from_fields(0, exponent_mask(), 64'h1 << (man_bits() - 1));
  endfunction

  static function automatic fma_word_t signaling_nan(bit sign = 0);
    return from_fields(sign, exponent_mask(), 1);
  endfunction

  static function automatic fpnew_pkg::roundmode_e random_roundmode();
    case ($urandom_range(4, 0))
      0: return fpnew_pkg::RNE;
      1: return fpnew_pkg::RTZ;
      2: return fpnew_pkg::RDN;
      3: return fpnew_pkg::RUP;
      default: return fpnew_pkg::RMM;
    endcase
  endfunction

  // raw_index covers the five RTL operation encodings and both modifier bits.
  static function automatic fpnew_pkg::operation_e raw_operation(int unsigned raw_index);
    case ((raw_index / 2) % 5)
      0: return fpnew_pkg::FMADD;
      1: return fpnew_pkg::FNMSUB;
      2: return fpnew_pkg::ADD;
      3: return fpnew_pkg::ADDS;
      default: return fpnew_pkg::MUL;
    endcase
  endfunction

  static function automatic bit raw_modifier(int unsigned raw_index);
    return bit'(raw_index & 1);
  endfunction

  // function_index covers the seven numerical functions. ADD and ADDS are one
  // numerical function here; their raw encodings are exercised separately.
  static function automatic fpnew_pkg::operation_e function_operation(int unsigned function_index);
    case (function_index % 7)
      0, 1: return fpnew_pkg::FMADD;
      2, 3: return fpnew_pkg::FNMSUB;
      4, 5: return fpnew_pkg::ADD;
      default: return fpnew_pkg::MUL;
    endcase
  endfunction

  static function automatic bit function_modifier(int unsigned function_index,
                                                    bit mul_modifier = 0);
    case (function_index % 7)
      1, 3, 5: return 1'b1;
      6:       return mul_modifier;
      default: return 1'b0;
    endcase
  endfunction

endclass

`endif

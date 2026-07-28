// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_DIRECTED_VIRTUAL_SEQUENCE_SVH
`define FMA_DIRECTED_VIRTUAL_SEQUENCE_SVH

class fma_directed_virtual_sequence extends fma_virtual_base_sequence;
  `uvm_object_utils(fma_directed_virtual_sequence)

  function new(string name = "fma_directed_virtual_sequence");
    super.new(name);
  endfunction

  protected function fma_word_t selected_result(int unsigned index);
    case (index)
      0:  return fma_operand_utils::positive_zero();
      1:  return fma_operand_utils::negative_zero();
      2:  return fma_operand_utils::min_subnormal(0);
      3:  return fma_operand_utils::min_subnormal(1);
      4:  return fma_operand_utils::middle_subnormal(0);
      5:  return fma_operand_utils::middle_subnormal(1);
      6:  return fma_operand_utils::max_subnormal(0);
      7:  return fma_operand_utils::max_subnormal(1);
      8:  return fma_operand_utils::min_normal(0);
      9:  return fma_operand_utils::min_normal(1);
      10: return fma_operand_utils::middle_normal(0);
      11: return fma_operand_utils::middle_normal(1);
      12: return fma_operand_utils::max_finite(0);
      13: return fma_operand_utils::max_finite(1);
      14: return fma_operand_utils::infinity(0);
      15: return fma_operand_utils::infinity(1);
      default: return fma_operand_utils::canonical_qnan();
    endcase
  endfunction

  // Configure any of the seven numerical functions to produce target exactly.
  // Matching signed zeros are used for the effective addend so the two zero
  // result bins are deterministic as well.
  protected function void configure_exact_result(
    fma_operation_item item,
    int unsigned       function_index,
    fma_word_t         target
  );
    bit target_sign;
    target_sign = target[FMA_WIDTH-1];

    item.operands[0] = target;
    item.operands[1] = fma_operand_utils::one();
    item.operands[2] = (target_sign ^ item.op_mod_i)
                     ? fma_operand_utils::negative_zero()
                     : fma_operand_utils::positive_zero();

    // FNMSUB/FNMADD negate the product in the DUT. Negating raw A here makes
    // the effective product equal target.
    if (function_index inside {2, 3})
      item.operands[0][FMA_WIDTH-1] = ~item.operands[0][FMA_WIDTH-1];

    // ADD/SUB ignores raw A and uses B as the value being preserved.
    if (function_index inside {4, 5})
      item.operands[1] = target;
  endfunction

  protected function void add_function_result_cross(
    ref fma_data_list_sequence list_seq,
    ref int unsigned           serial
  );
    for (int function_index = 0; function_index < 7; function_index++) begin
      for (int result_index = 0; result_index < 17; result_index++) begin
        fma_operation_item item;
        item = make_function_item(function_index, serial++, result_index[0]);
        configure_exact_result(item, function_index, selected_result(result_index));
        list_seq.add(item);
      end
    end
  endfunction

  protected function fma_operation_item make_status_item(
    int unsigned             function_index,
    int unsigned             status_index,
    fpnew_pkg::roundmode_e   rnd_mode,
    ref int unsigned         serial
  );
    fma_operation_item item;
    fma_word_t next_after_one;
    bit mul_modifier;

    mul_modifier = serial[0];
    item = make_function_item(function_index, serial, mul_modifier);
    serial++;
    item.rnd_mode = rnd_mode;
    // Raw C sign equal to op_mod gives an effective +0 addend.
    item.operands[2] = item.op_mod_i ? fma_operand_utils::negative_zero()
                                     : fma_operand_utils::positive_zero();
    next_after_one = fma_operand_utils::from_fields(
      0, (64'h1 << (fma_operand_utils::exp_bits() - 1)) - 1, 1);

    case (status_index)
      0: begin // NX without overflow or underflow
        if (function_index inside {4, 5}) begin
          item.operands[1] = fma_operand_utils::one();
          item.operands[2] = item.op_mod_i
                           ? fma_operand_utils::min_subnormal(1)
                           : fma_operand_utils::min_subnormal(0);
        end else begin
          item.operands[0] = next_after_one;
          item.operands[1] = next_after_one;
        end
      end
      1: begin // UF+NX; only requested for FMA and MUL
        item.operands[0] = fma_operand_utils::min_normal();
        item.operands[1] = fma_operand_utils::min_normal();
      end
      2: begin // OF+NX
        if (function_index inside {4, 5}) begin
          item.operands[1] = fma_operand_utils::max_finite();
          item.operands[2] = item.op_mod_i
                           ? fma_operand_utils::max_finite(1)
                           : fma_operand_utils::max_finite(0);
        end else begin
          item.operands[0] = fma_operand_utils::max_finite();
          item.operands[1] = fma_operand_utils::two();
        end
      end
      default: begin // NV from a signalling NaN in an operand the function uses
        if (function_index inside {4, 5})
          item.operands[1] = fma_operand_utils::signaling_nan();
        else
          item.operands[0] = fma_operand_utils::signaling_nan();
      end
    endcase
    return item;
  endfunction

  protected function void add_function_status_cross(
    ref fma_data_list_sequence list_seq,
    ref int unsigned           serial
  );
    for (int function_index = 0; function_index < 7; function_index++) begin
      // Every function can produce NX, OF+NX and NV.
      list_seq.add(make_status_item(function_index, 0, fpnew_pkg::RNE, serial));
      list_seq.add(make_status_item(function_index, 2, fpnew_pkg::RNE, serial));
      list_seq.add(make_status_item(function_index, 3, fpnew_pkg::RNE, serial));
      // Same-format ADD/SUB cannot produce UF+NX; that cross bin is ignored.
      if (!(function_index inside {4, 5}))
        list_seq.add(make_status_item(function_index, 1, fpnew_pkg::RNE, serial));
    end
  endfunction

  protected function void add_rounding_status_cross(
    ref fma_data_list_sequence list_seq,
    ref int unsigned           serial
  );
    fpnew_pkg::roundmode_e modes[5] = '{fpnew_pkg::RNE, fpnew_pkg::RTZ,
                                          fpnew_pkg::RDN, fpnew_pkg::RUP,
                                          fpnew_pkg::RMM};
    foreach (modes[rm]) begin
      // ADD supplies an NX-only case; MUL supplies tiny and overflowing cases.
      list_seq.add(make_status_item(4, 0, modes[rm], serial));
      list_seq.add(make_status_item(6, 1, modes[rm], serial));
      list_seq.add(make_status_item(6, 2, modes[rm], serial));
    end
  endfunction

  protected function void add_result_status_cross(
    ref fma_data_list_sequence list_seq,
    ref int unsigned           serial
  );
    fma_operation_item item;
    fma_word_t target;
    bit sign;

    // UF+NX rounded to each signed zero/subnormal boundary.
    for (int result_index = 0; result_index < 8; result_index++) begin
      target = selected_result(result_index);
      sign = target[FMA_WIDTH-1];
      item = make_function_item(0, serial++);
      item.operands[0] = fma_operand_utils::min_normal(sign);
      item.operands[1] = fma_operand_utils::min_normal();
      item.operands[2] = target;
      list_seq.add(item);
    end

    // For min normal, a same-sign tiny correction gives NX only; an
    // opposite-sign correction leaves an exact tiny value that rounds back to
    // min normal and gives UF+NX.
    for (int result_index = 8; result_index <= 9; result_index++) begin
      target = selected_result(result_index);
      sign = target[FMA_WIDTH-1];
      item = make_function_item(0, serial++);
      item.operands[0] = fma_operand_utils::min_normal(sign);
      item.operands[1] = fma_operand_utils::min_normal();
      item.operands[2] = target;
      list_seq.add(item);

      item = make_function_item(0, serial++);
      item.operands[0] = fma_operand_utils::min_normal(!sign);
      // The product is exactly half of min_subnormal. The exact result is the
      // midpoint between max subnormal and min normal; RNE selects min normal
      // and the DUT/SoftFloat after-rounding tiny test raises UF+NX.
      item.operands[1] = fma_operand_utils::half_min_subnormal_factor();
      item.operands[2] = target;
      list_seq.add(item);
    end

    // Middle normals retain the selected result after a same-sign tiny
    // correction and set NX. Max finite uses the opposite sign to stay finite.
    for (int result_index = 10; result_index <= 13; result_index++) begin
      target = selected_result(result_index);
      sign = target[FMA_WIDTH-1];
      item = make_function_item(0, serial++);
      item.operands[0] = fma_operand_utils::min_normal(
        (result_index >= 12) ? !sign : sign);
      item.operands[1] = fma_operand_utils::min_normal();
      item.operands[2] = target;
      list_seq.add(item);
    end

    // Overflow can round to max finite (RTZ) or infinity (RNE), for both signs.
    for (int sign_index = 0; sign_index < 2; sign_index++) begin
      item = make_function_item(6, serial++);
      item.rnd_mode = fpnew_pkg::RTZ;
      item.operands[0] = fma_operand_utils::max_finite(sign_index[0]);
      item.operands[1] = fma_operand_utils::two();
      list_seq.add(item);

      item = make_function_item(6, serial++);
      item.rnd_mode = fpnew_pkg::RNE;
      item.operands[0] = fma_operand_utils::max_finite(sign_index[0]);
      item.operands[1] = fma_operand_utils::two();
      list_seq.add(item);
    end

    // A signalling NaN produces canonical qNaN with NV.
    item = make_function_item(6, serial++);
    item.operands[0] = fma_operand_utils::signaling_nan();
    item.operands[1] = fma_operand_utils::one();
    list_seq.add(item);
  endfunction

  protected function void add_special_cases(ref fma_data_list_sequence list_seq,
                                             ref int unsigned serial);
    fma_operation_item item;

    // Invalid multiplication combined with each NaN source.
    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::infinity();
    item.operands[1] = fma_operand_utils::positive_zero();
    item.operands[2] = fma_operand_utils::canonical_qnan();
    list_seq.add(item);

    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::infinity();
    item.operands[1] = fma_operand_utils::positive_zero();
    item.operands[2] = fma_operand_utils::signaling_nan();
    list_seq.add(item);

    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::infinity();
    item.operands[1] = fma_operand_utils::positive_zero();
    item.is_boxed[2] = 1'b0;
    list_seq.add(item);

    // NaN/bad-boxing with infinity, multiple NaNs, and infinite addends.
    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::canonical_qnan();
    item.operands[1] = fma_operand_utils::infinity();
    item.operands[2] = fma_operand_utils::infinity();
    list_seq.add(item);

    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::signaling_nan();
    item.operands[1] = fma_operand_utils::canonical_qnan();
    item.operands[2] = fma_operand_utils::infinity();
    list_seq.add(item);

    // Bad boxing and infinity are present together without relying on Inf*0.
    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::one();
    item.is_boxed[0] = 1'b0;
    item.operands[1] = fma_operand_utils::infinity();
    item.operands[2] = fma_operand_utils::positive_zero();
    list_seq.add(item);

    // Infinite product plus opposite-sign infinity is invalid; same sign is not.
    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::infinity(0);
    item.operands[1] = fma_operand_utils::one();
    item.operands[2] = fma_operand_utils::infinity(1);
    list_seq.add(item);

    item = make_function_item(0, serial++);
    item.operands[0] = fma_operand_utils::infinity(0);
    item.operands[1] = fma_operand_utils::one();
    item.operands[2] = fma_operand_utils::infinity(0);
    list_seq.add(item);
  endfunction

  protected function void add_ignored_operand_pairs(ref fma_data_list_sequence list_seq,
                                                     ref int unsigned serial);
    // ADD and ADDS must ignore original A even when its raw bits or boxing change.
    for (int raw_add = 0; raw_add < 2; raw_add++) begin
      for (int mod = 0; mod < 2; mod++) begin
        for (int cls = 0; cls < 12; cls++) begin
          for (int boxed = 0; boxed < 2; boxed++) begin
            fma_operation_item baseline;
            fma_operation_item varied;
            baseline = make_function_item(4 + mod, serial++);
            baseline.op_i = raw_add ? fpnew_pkg::ADDS : fpnew_pkg::ADD;
            baseline.operands[0] = fma_operand_utils::one();
            baseline.is_boxed[0] = 1'b1;
            varied = make_function_item(4 + mod, serial++);
            varied.op_i = baseline.op_i;
            varied.operands[0] = fma_operand_utils::value_of_class(fma_operand_class_e'(cls));
            varied.is_boxed[0] = boxed;
            list_seq.add(baseline);
            list_seq.add(varied);
          end
        end
      end
    end

    // MUL must ignore original C, for both modifier encodings.
    for (int mod = 0; mod < 2; mod++) begin
      for (int cls = 0; cls < 12; cls++) begin
        for (int boxed = 0; boxed < 2; boxed++) begin
          fma_operation_item baseline;
          fma_operation_item varied;
          baseline = make_function_item(6, serial++, mod);
          baseline.operands[2] = fma_operand_utils::positive_zero();
          baseline.is_boxed[2] = 1'b1;
          varied = make_function_item(6, serial++, mod);
          varied.operands[2] = fma_operand_utils::value_of_class(fma_operand_class_e'(cls));
          varied.is_boxed[2] = boxed;
          list_seq.add(baseline);
          list_seq.add(varied);
        end
      end
    end
  endfunction

  protected function void add_boundary_cases(ref fma_data_list_sequence list_seq,
                                              ref int unsigned serial);
    fma_word_t boundaries[6];
    fpnew_pkg::roundmode_e modes[5] = '{fpnew_pkg::RNE, fpnew_pkg::RTZ,
                                          fpnew_pkg::RDN, fpnew_pkg::RUP,
                                          fpnew_pkg::RMM};
    boundaries = '{fma_operand_utils::min_subnormal(),
                   fma_operand_utils::max_subnormal(),
                   fma_operand_utils::min_normal(),
                   fma_operand_utils::max_finite(),
                   fma_operand_utils::min_subnormal(1),
                   fma_operand_utils::max_finite(1)};
    foreach (boundaries[b]) begin
      foreach (modes[rm]) begin
        for (int function_index = 0; function_index < 7; function_index++) begin
          fma_operation_item item;
          item = make_function_item(function_index, serial++, rm[0]);
          item.rnd_mode = modes[rm];
          item.operands[2] = boundaries[b];
          list_seq.add(item);
        end
      end
    end
  endfunction

  virtual task body();
    fma_data_list_sequence data_sequence;
    fma_ready_always_sequence ready_sequence;
    int unsigned serial;

    initial_reset();
    data_sequence  = fma_data_list_sequence::type_id::create("data_sequence");
    ready_sequence = fma_ready_always_sequence::type_id::create("ready_sequence");

    // 3 operands x 7 numerical functions x 12 classes x 2 boxing states = 504.
    for (int operand_index = 0; operand_index < 3; operand_index++) begin
      for (int function_index = 0; function_index < 7; function_index++) begin
        for (int cls = 0; cls < 12; cls++) begin
          for (int boxed = 0; boxed < 2; boxed++) begin
            fma_operation_item item;
            bit mul_modifier;
            mul_modifier = serial[0];
            item = make_function_item(function_index, serial, mul_modifier);
            serial++;
            item.operands[operand_index] =
              fma_operand_utils::value_of_class(fma_operand_class_e'(cls));
            item.is_boxed[operand_index] = boxed;
            data_sequence.add(item);
          end
        end
      end
    end

    // 7 numerical functions x all eight boxing vectors = 56.
    for (int function_index = 0; function_index < 7; function_index++) begin
      for (int boxing = 0; boxing < 8; boxing++) begin
        fma_operation_item item;
        item = make_function_item(function_index, serial++, boxing[0]);
        item.is_boxed = boxing[2:0];
        data_sequence.add(item);
      end
    end

    add_special_cases(data_sequence, serial);
    add_ignored_operand_pairs(data_sequence, serial);
    add_boundary_cases(data_sequence, serial);
    add_function_result_cross(data_sequence, serial);
    add_function_status_cross(data_sequence, serial);
    add_rounding_status_cross(data_sequence, serial);
    add_result_status_cross(data_sequence, serial);

    ready_sequence.start(p_sequencer.ready_sequencer);
    data_sequence.start(p_sequencer.data_sequencer);
    leave_safe_controls();
  endtask
endclass

`endif

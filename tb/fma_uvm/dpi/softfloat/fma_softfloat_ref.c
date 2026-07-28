// SPDX-License-Identifier: BSD-3-Clause

#include <stdint.h>

#include "fma_ref_api.h"
#include "softfloat.h"

#define SIGN16 UINT16_C(0x8000)
#define SIGN32 UINT32_C(0x80000000)
#define SIGN64 UINT64_C(0x8000000000000000)

static uint_fast8_t map_rounding_mode(unsigned int rtl_rm)
{
    switch (rtl_rm) {
    case 0: return softfloat_round_near_even;
    case 1: return softfloat_round_minMag;
    case 2: return softfloat_round_min;
    case 3: return softfloat_round_max;
    case 4: return softfloat_round_near_maxMag;
    default: return UINT8_MAX;
    }
}

static unsigned char pack_flags(uint_fast8_t flags)
{
    unsigned char packed = 0;
    if (flags & softfloat_flag_invalid)   packed |= 0x10;
    if (flags & softfloat_flag_infinite)  packed |= 0x08;
    if (flags & softfloat_flag_overflow)  packed |= 0x04;
    if (flags & softfloat_flag_underflow) packed |= 0x02;
    if (flags & softfloat_flag_inexact)   packed |= 0x01;
    return packed;
}

static int prepare(unsigned int rounding_mode, uint_fast8_t *softfloat_rm,
                   uint64_t *result, unsigned char *status)
{
    if (!softfloat_rm || !result || !status) return FMA_REF_BAD_REQUEST;
    *softfloat_rm = map_rounding_mode(rounding_mode);
    if (*softfloat_rm == UINT8_MAX) return FMA_REF_UNSUPPORTED_RM;

    softfloat_roundingMode = *softfloat_rm;
    softfloat_detectTininess = softfloat_tininess_afterRounding;
    softfloat_exceptionFlags = 0;
    *result = 0;
    *status = 0;
    return FMA_REF_OK;
}

static float16_t f16(uint64_t bits)
{
    float16_t value;
    value.v = (uint16_t)bits;
    return value;
}

static float32_t f32(uint64_t bits)
{
    float32_t value;
    value.v = (uint32_t)bits;
    return value;
}

static float64_t f64(uint64_t bits)
{
    float64_t value;
    value.v = bits;
    return value;
}

static int eval_f16(unsigned int function_code, uint64_t a_bits,
                    uint64_t b_bits, uint64_t c_bits, uint64_t *result)
{
    float16_t value;

    switch (function_code) {
    case FMA_REF_FMADD:
        value = f16_mulAdd(f16(a_bits), f16(b_bits), f16(c_bits));
        break;
    case FMA_REF_FMSUB:
        value = f16_mulAdd(f16(a_bits), f16(b_bits), f16(c_bits ^ SIGN16));
        break;
    case FMA_REF_FNMSUB:
        value = f16_mulAdd(f16(a_bits ^ SIGN16), f16(b_bits), f16(c_bits));
        break;
    case FMA_REF_FNMADD:
        value = f16_mulAdd(f16(a_bits ^ SIGN16), f16(b_bits), f16(c_bits ^ SIGN16));
        break;
    case FMA_REF_ADD:
        value = f16_add(f16(b_bits), f16(c_bits));
        break;
    case FMA_REF_SUB:
        value = f16_sub(f16(b_bits), f16(c_bits));
        break;
    case FMA_REF_MUL:
        value = f16_mul(f16(a_bits), f16(b_bits));
        break;
    default:
        return FMA_REF_UNSUPPORTED_FUNCTION;
    }
    *result = value.v;
    return FMA_REF_OK;
}

static int eval_f32(unsigned int function_code, uint64_t a_bits,
                    uint64_t b_bits, uint64_t c_bits, uint64_t *result)
{
    float32_t value;

    switch (function_code) {
    case FMA_REF_FMADD:
        value = f32_mulAdd(f32(a_bits), f32(b_bits), f32(c_bits));
        break;
    case FMA_REF_FMSUB:
        value = f32_mulAdd(f32(a_bits), f32(b_bits), f32(c_bits ^ SIGN32));
        break;
    case FMA_REF_FNMSUB:
        value = f32_mulAdd(f32(a_bits ^ SIGN32), f32(b_bits), f32(c_bits));
        break;
    case FMA_REF_FNMADD:
        value = f32_mulAdd(f32(a_bits ^ SIGN32), f32(b_bits), f32(c_bits ^ SIGN32));
        break;
    case FMA_REF_ADD:
        value = f32_add(f32(b_bits), f32(c_bits));
        break;
    case FMA_REF_SUB:
        value = f32_sub(f32(b_bits), f32(c_bits));
        break;
    case FMA_REF_MUL:
        value = f32_mul(f32(a_bits), f32(b_bits));
        break;
    default:
        return FMA_REF_UNSUPPORTED_FUNCTION;
    }
    *result = value.v;
    return FMA_REF_OK;
}

static int eval_f64(unsigned int function_code, uint64_t a_bits,
                    uint64_t b_bits, uint64_t c_bits, uint64_t *result)
{
    float64_t value;

    switch (function_code) {
    case FMA_REF_FMADD:
        value = f64_mulAdd(f64(a_bits), f64(b_bits), f64(c_bits));
        break;
    case FMA_REF_FMSUB:
        value = f64_mulAdd(f64(a_bits), f64(b_bits), f64(c_bits ^ SIGN64));
        break;
    case FMA_REF_FNMSUB:
        value = f64_mulAdd(f64(a_bits ^ SIGN64), f64(b_bits), f64(c_bits));
        break;
    case FMA_REF_FNMADD:
        value = f64_mulAdd(f64(a_bits ^ SIGN64), f64(b_bits), f64(c_bits ^ SIGN64));
        break;
    case FMA_REF_ADD:
        value = f64_add(f64(b_bits), f64(c_bits));
        break;
    case FMA_REF_SUB:
        value = f64_sub(f64(b_bits), f64(c_bits));
        break;
    case FMA_REF_MUL:
        value = f64_mul(f64(a_bits), f64(b_bits));
        break;
    default:
        return FMA_REF_UNSUPPORTED_FUNCTION;
    }
    *result = value.v;
    return FMA_REF_OK;
}

int fma_softfloat_eval(unsigned int format, unsigned int function_code,
                       unsigned int rounding_mode, uint64_t operand_a,
                       uint64_t operand_b, uint64_t operand_c,
                       uint64_t *result, unsigned char *status)
{
    uint_fast8_t softfloat_rm;
    int rc = prepare(rounding_mode, &softfloat_rm, result, status);
    (void)softfloat_rm;
    if (rc != FMA_REF_OK) return rc;

    switch (format) {
    case FMA_REF_FP16:
        rc = eval_f16(function_code, operand_a, operand_b, operand_c, result);
        break;
    case FMA_REF_FP32:
        rc = eval_f32(function_code, operand_a, operand_b, operand_c, result);
        break;
    case FMA_REF_FP64:
        rc = eval_f64(function_code, operand_a, operand_b, operand_c, result);
        break;
    default:
        return FMA_REF_UNSUPPORTED_FORMAT;
    }

    if (rc == FMA_REF_OK) *status = pack_flags(softfloat_exceptionFlags);
    return rc;
}

const char *fma_softfloat_model_version(void)
{
    return "Berkeley SoftFloat Release 3e, RISCV specialization";
}

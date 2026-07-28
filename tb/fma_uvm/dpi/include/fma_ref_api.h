// SPDX-License-Identifier: BSD-3-Clause
#ifndef FMA_REF_API_H
#define FMA_REF_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum fma_ref_rc {
    FMA_REF_OK = 0,
    FMA_REF_UNSUPPORTED_FORMAT = 1,
    FMA_REF_UNSUPPORTED_FUNCTION = 2,
    FMA_REF_UNSUPPORTED_RM = 3,
    FMA_REF_BAD_REQUEST = 4
};

/* Values deliberately match fpnew_pkg::fp_format_e. */
enum fma_ref_format {
    FMA_REF_FP32 = 0,
    FMA_REF_FP64 = 1,
    FMA_REF_FP16 = 2
};

/* Values deliberately match fma_types_pkg::fma_function_e. */
enum fma_ref_function {
    FMA_REF_FMADD = 0,
    FMA_REF_FMSUB = 1,
    FMA_REF_FNMSUB = 2,
    FMA_REF_FNMADD = 3,
    FMA_REF_ADD = 4,
    FMA_REF_SUB = 5,
    FMA_REF_MUL = 6
};

/*
 * Unified DPI entry point.  Operands and result use a fixed 64-bit ABI; only
 * the low 16, 32, or 64 bits are meaningful for the selected format.
 * status is packed as {NV,DZ,OF,UF,NX} in bits [4:0].
 */
int fma_softfloat_eval(unsigned int format,
                       unsigned int function_code,
                       unsigned int rounding_mode,
                       uint64_t operand_a,
                       uint64_t operand_b,
                       uint64_t operand_c,
                       uint64_t *result,
                       unsigned char *status);

const char *fma_softfloat_model_version(void);

#ifdef __cplusplus
}
#endif
#endif

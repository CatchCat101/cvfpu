// SPDX-License-Identifier: BSD-3-Clause

#include <inttypes.h>
#include <stdio.h>

#include "fma_ref_api.h"

struct format_case {
    unsigned int format;
    uint64_t one;
    uint64_t one_point_five;
    uint64_t two;
    uint64_t half;
    uint64_t three_point_five;
    uint64_t infinity;
    uint64_t max_finite;
    uint64_t min_subnormal;
    uint64_t half_ulp_at_one;
    uint64_t one_plus_ulp;
};

static int check_eval(const struct format_case *fc, unsigned int function_code,
                      unsigned int rm, uint64_t a, uint64_t b, uint64_t c,
                      uint64_t expected, unsigned char expected_status,
                      const char *description)
{
    uint64_t result = 0;
    unsigned char status = 0;
    int rc = fma_softfloat_eval(fc->format, function_code, rm, a, b, c,
                                &result, &status);
    if (rc || result != expected || status != expected_status) {
        fprintf(stderr,
                "FAIL format=%u %s: rc=%d result=%016" PRIx64
                " status=%02x expected=%016" PRIx64 "/%02x\n",
                fc->format, description, rc, result, status, expected,
                expected_status);
        return 1;
    }
    return 0;
}

int main(void)
{
    static const struct format_case cases[] = {
        {FMA_REF_FP16, UINT64_C(0x3c00), UINT64_C(0x3e00), UINT64_C(0x4000),
         UINT64_C(0x3800), UINT64_C(0x4300), UINT64_C(0x7c00),
         UINT64_C(0x7bff), UINT64_C(0x0001), UINT64_C(0x1000),
         UINT64_C(0x3c01)},
        {FMA_REF_FP32, UINT64_C(0x3f800000), UINT64_C(0x3fc00000),
         UINT64_C(0x40000000), UINT64_C(0x3f000000), UINT64_C(0x40600000),
         UINT64_C(0x7f800000), UINT64_C(0x7f7fffff), UINT64_C(0x00000001),
         UINT64_C(0x33800000), UINT64_C(0x3f800001)},
        {FMA_REF_FP64, UINT64_C(0x3ff0000000000000),
         UINT64_C(0x3ff8000000000000), UINT64_C(0x4000000000000000),
         UINT64_C(0x3fe0000000000000), UINT64_C(0x400c000000000000),
         UINT64_C(0x7ff0000000000000), UINT64_C(0x7fefffffffffffff),
         UINT64_C(0x0000000000000001), UINT64_C(0x3ca0000000000000),
         UINT64_C(0x3ff0000000000001)}
    };
    unsigned int i;
    unsigned int rm;
    int failures = 0;

    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        const struct format_case *fc = &cases[i];
        for (rm = 0; rm <= 4; ++rm) {
            failures += check_eval(fc, FMA_REF_FMADD, rm, fc->one_point_five,
                                   fc->two, fc->half, fc->three_point_five,
                                   0x00, "exact FMA in all rounding modes");
        }
        failures += check_eval(fc, FMA_REF_MUL, 0, fc->infinity, 0, 0,
                               fc->infinity | (fc->format == FMA_REF_FP16
                                   ? UINT64_C(0x0200)
                                   : fc->format == FMA_REF_FP32
                                       ? UINT64_C(0x00400000)
                                       : UINT64_C(0x0008000000000000)),
                               0x10, "infinity times zero is invalid");
        failures += check_eval(fc, FMA_REF_MUL, 0, fc->max_finite, fc->two, 0,
                               fc->infinity, 0x05, "overflow after rounding");
        failures += check_eval(fc, FMA_REF_MUL, 0, fc->min_subnormal, fc->half,
                               0, 0, 0x03, "tiny and inexact result");
        failures += check_eval(fc, FMA_REF_ADD, 4, 0, fc->one,
                               fc->half_ulp_at_one, fc->one_plus_ulp, 0x01,
                               "RMM tie rounds away from zero");
    }

    if (failures) return 1;
    puts("SoftFloat FMA adapter self-test passed for FP16, FP32 and FP64");
    return 0;
}

// SPDX-License-Identifier: SHL-0.51

`ifdef FMA_FORMAT_FP8
  `error "FMA_FORMAT_FP8 is not supported by the SoftFloat single-format FMA environment"
`endif
`ifdef FMA_FORMAT_FP16ALT
  `error "FMA_FORMAT_FP16ALT is not supported by the SoftFloat single-format FMA environment"
`endif

`ifdef FMA_FORMAT_FP16
  `ifdef FMA_FORMAT_FP32
    `error "Define exactly one of FMA_FORMAT_FP16, FMA_FORMAT_FP32, or FMA_FORMAT_FP64"
  `endif
  `ifdef FMA_FORMAT_FP64
    `error "Define exactly one of FMA_FORMAT_FP16, FMA_FORMAT_FP32, or FMA_FORMAT_FP64"
  `endif
`endif

`ifdef FMA_FORMAT_FP32
  `ifdef FMA_FORMAT_FP64
    `error "Define exactly one of FMA_FORMAT_FP16, FMA_FORMAT_FP32, or FMA_FORMAT_FP64"
  `endif
`endif

// Keep editors and one-off compile commands useful. Production builds always
// pass one of the three format macros explicitly.
`ifndef FMA_FORMAT_FP16
  `ifndef FMA_FORMAT_FP32
    `ifndef FMA_FORMAT_FP64
      `define FMA_FORMAT_FP32
    `endif
  `endif
`endif

package fma_config_pkg;
  `ifdef FMA_FORMAT_FP16
    localparam fpnew_pkg::fp_format_e FMA_FORMAT = fpnew_pkg::FP16;
  `elsif FMA_FORMAT_FP64
    localparam fpnew_pkg::fp_format_e FMA_FORMAT = fpnew_pkg::FP64;
  `else
    localparam fpnew_pkg::fp_format_e FMA_FORMAT = fpnew_pkg::FP32;
  `endif

  localparam int unsigned FMA_WIDTH     = fpnew_pkg::fp_width(FMA_FORMAT);
  localparam int unsigned FMA_TAG_WIDTH = 8;
  localparam int unsigned FMA_AUX_WIDTH = 8;

  typedef logic [FMA_WIDTH-1:0]     fma_word_t;
  typedef logic [FMA_TAG_WIDTH-1:0] fma_tag_t;
  typedef logic [FMA_AUX_WIDTH-1:0] fma_aux_t;
endpackage

// SPDX-License-Identifier: SHL-0.51

bind fpnew_fma fma_pipeline_checker #(
  .NumInpRegs(NUM_INP_REGS),
  .NumMidRegs(NUM_MID_REGS),
  .NumOutRegs(NUM_OUT_REGS)
) i_fma_pipeline_checker (
  .clk_i,
  .rst_ni,
  .early_out_valid_o,
  .inp_valid_q(inp_pipe_valid_q),
  .inp_ready(inp_pipe_ready),
  .mid_valid_q(mid_pipe_valid_q),
  .mid_ready(mid_pipe_ready),
  .out_valid_q(out_pipe_valid_q),
  .out_ready(out_pipe_ready)
);

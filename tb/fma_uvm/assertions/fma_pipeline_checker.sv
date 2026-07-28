// SPDX-License-Identifier: SHL-0.51

// This checker intentionally implements the interface contract, not the current
// RTL expression.  In particular, the terminal ready signal must come from the
// same pipeline section as the terminal valid signal.  The known n2_inside RTL
// defect is therefore visible instead of being copied into the checker.
module fma_pipeline_checker #(
  parameter int unsigned NumInpRegs = 0,
  parameter int unsigned NumMidRegs = 0,
  parameter int unsigned NumOutRegs = 0
) (
  input logic clk_i,
  input logic rst_ni,
  input logic early_out_valid_o,
  input logic [0:NumInpRegs] inp_valid_q,
  input logic [0:NumInpRegs] inp_ready,
  input logic [0:NumMidRegs] mid_valid_q,
  input logic [0:NumMidRegs] mid_ready,
  input logic [0:NumOutRegs] out_valid_q,
  input logic [0:NumOutRegs] out_ready
);
  if (NumOutRegs > 0) begin : gen_output_terminal
    a_early_out_valid: assert property (@(posedge clk_i) disable iff (!rst_ni)
      early_out_valid_o ==
        ((out_valid_q[NumOutRegs] && !out_ready[NumOutRegs]) ||
         out_valid_q[NumOutRegs-1]));
  end else if (NumMidRegs > 0) begin : gen_middle_terminal
    a_early_out_valid: assert property (@(posedge clk_i) disable iff (!rst_ni)
      early_out_valid_o ==
        ((mid_valid_q[NumMidRegs] && !mid_ready[NumMidRegs]) ||
         mid_valid_q[NumMidRegs-1]));
  end else if (NumInpRegs > 0) begin : gen_input_terminal
    a_early_out_valid: assert property (@(posedge clk_i) disable iff (!rst_ni)
      early_out_valid_o ==
        ((inp_valid_q[NumInpRegs] && !inp_ready[NumInpRegs]) ||
         inp_valid_q[NumInpRegs-1]));
  end else begin : gen_no_pipeline_registers
    a_early_out_valid: assert property (@(posedge clk_i) disable iff (!rst_ni)
      !early_out_valid_o);
  end
endmodule

// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_RANDOM_CONTROL_SEQUENCE_SVH
`define FMA_RANDOM_CONTROL_SEQUENCE_SVH

class fma_random_control_sequence extends fma_control_base_sequence;
  `uvm_object_utils(fma_random_control_sequence)

  int unsigned total_cycles = 10000;
  int unsigned flush_per_thousand = 12;
  int unsigned reset_per_thousand = 3;

  function new(string name = "fma_random_control_sequence");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned elapsed;
    while (elapsed < total_cycles) begin
      int unsigned draw;
      int unsigned run;
      draw = $urandom_range(999, 0);
      if (draw < reset_per_thousand) begin
        run = $urandom_range(4, 2);
        send_state(1'b0, ($urandom_range(3, 0) == 0), run);
      end else if (draw < reset_per_thousand + flush_per_thousand) begin
        run = $urandom_range(3, 1);
        send_state(1'b1, 1'b1, run);
      end else begin
        run = $urandom_range(24, 4);
        if (run > total_cycles - elapsed) run = total_cycles - elapsed;
        send_state(1'b1, 1'b0, run);
      end
      elapsed += run;
    end
    send_state(1'b1, 1'b0, 1);
  endtask
endclass

`endif

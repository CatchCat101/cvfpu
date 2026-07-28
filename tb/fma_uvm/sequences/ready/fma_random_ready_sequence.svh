// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_RANDOM_READY_SEQUENCE_SVH
`define FMA_RANDOM_READY_SEQUENCE_SVH

class fma_random_ready_sequence extends fma_ready_base_sequence;
  `uvm_object_utils(fma_random_ready_sequence)

  int unsigned total_cycles = 2000;
  int unsigned max_low_cycles = 16;
  int unsigned max_high_cycles = 16;

  function new(string name = "fma_random_ready_sequence");
    super.new(name);
  endfunction

  virtual task body();
    int unsigned elapsed;
    bit ready;
    ready = 1'b1;
    while (elapsed < total_cycles) begin
      int unsigned run;
      run = ready ? $urandom_range(max_high_cycles, 1)
                  : $urandom_range(max_low_cycles, 1);
      if (run > total_cycles - elapsed) run = total_cycles - elapsed;
      send_segment(ready, run);
      elapsed += run;
      ready = ~ready;
    end
    // The ready driver holds the last segment after the sequence ends.
    send_segment(1'b1, 1);
  endtask
endclass

`endif

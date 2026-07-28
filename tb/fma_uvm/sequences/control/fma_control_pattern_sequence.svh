// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_CONTROL_PATTERN_SEQUENCE_SVH
`define FMA_CONTROL_PATTERN_SEQUENCE_SVH

class fma_control_pattern_sequence extends fma_control_base_sequence;
  `uvm_object_utils(fma_control_pattern_sequence)

  fma_control_item states[$];

  function new(string name = "fma_control_pattern_sequence");
    super.new(name);
  endfunction

  function void add(bit rst_ni, bit flush_i, int unsigned cycles = 1);
    fma_control_item item;
    item = fma_control_item::type_id::create($sformatf("state_%0d", states.size()));
    item.rst_ni  = rst_ni;
    item.flush_i = flush_i;
    item.cycles  = (cycles == 0) ? 1 : cycles;
    states.push_back(item);
  endfunction

  virtual task body();
    foreach (states[i]) begin
      start_item(states[i]);
      finish_item(states[i]);
    end
  endtask
endclass

`endif

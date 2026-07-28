// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_READY_PATTERN_SEQUENCE_SVH
`define FMA_READY_PATTERN_SEQUENCE_SVH

class fma_ready_pattern_sequence extends fma_ready_base_sequence;
  `uvm_object_utils(fma_ready_pattern_sequence)

  fma_ready_item segments[$];

  function new(string name = "fma_ready_pattern_sequence");
    super.new(name);
  endfunction

  function void add(bit ready, int unsigned cycles = 1);
    fma_ready_item item;
    item = fma_ready_item::type_id::create($sformatf("segment_%0d", segments.size()));
    item.ready  = ready;
    item.cycles = (cycles == 0) ? 1 : cycles;
    segments.push_back(item);
  endfunction

  virtual task body();
    foreach (segments[i]) begin
      start_item(segments[i]);
      finish_item(segments[i]);
    end
  endtask
endclass

`endif

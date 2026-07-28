// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_SMOKE_VIRTUAL_SEQUENCE_SVH
`define FMA_SMOKE_VIRTUAL_SEQUENCE_SVH

class fma_smoke_virtual_sequence extends fma_virtual_base_sequence;
  `uvm_object_utils(fma_smoke_virtual_sequence)

  function new(string name = "fma_smoke_virtual_sequence");
    super.new(name);
  endfunction

  virtual task body();
    fma_data_list_sequence data_sequence;
    fma_ready_always_sequence ready_sequence;
    fpnew_pkg::roundmode_e modes[5] = '{fpnew_pkg::RNE, fpnew_pkg::RTZ,
                                          fpnew_pkg::RDN, fpnew_pkg::RUP,
                                          fpnew_pkg::RMM};
    int unsigned serial;

    initial_reset();
    data_sequence  = fma_data_list_sequence::type_id::create("data_sequence");
    ready_sequence = fma_ready_always_sequence::type_id::create("ready_sequence");
    for (int unsigned raw_index = 0; raw_index < 10; raw_index++) begin
      foreach (modes[rm]) begin
        fma_operation_item item;
        item = make_raw_item(raw_index, modes[rm], serial++);
        data_sequence.add(item, (serial % 7) == 0);
      end
    end
    ready_sequence.start(p_sequencer.ready_sequencer);
    data_sequence.start(p_sequencer.data_sequencer);
    leave_safe_controls();
  endtask
endclass

`endif

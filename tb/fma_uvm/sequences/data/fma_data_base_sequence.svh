// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_DATA_BASE_SEQUENCE_SVH
`define FMA_DATA_BASE_SEQUENCE_SVH

class fma_data_base_sequence extends uvm_sequence #(fma_operation_item,
                                                     fma_data_response);
  `uvm_object_utils(fma_data_base_sequence)
  `uvm_declare_p_sequencer(fma_data_sequencer)

  int unsigned accepted_count;
  int unsigned canceled_count;

  function new(string name = "fma_data_base_sequence");
    super.new(name);
  endfunction

  virtual task wait_before_item(int unsigned cycles);
    repeat (cycles) @(posedge p_sequencer.vif.clk_i);
  endtask

  virtual task send_operation(fma_operation_item item, int unsigned gap_cycles = 0);
    fma_data_response response;
    wait_before_item(gap_cycles);
    start_item(item);
    finish_item(item);
    get_response(response);
    if (response.completion == FMA_DATA_ACCEPTED)
      accepted_count++;
    else
      canceled_count++;
  endtask

  virtual function fma_operation_item make_operation(
    fpnew_pkg::operation_e op_i,
    bit op_mod_i,
    fpnew_pkg::roundmode_e rnd_mode = fpnew_pkg::RNE
  );
    fma_operation_item item;
    item = fma_operation_item::type_id::create("item");
    item.op_i       = op_i;
    item.op_mod_i   = op_mod_i;
    item.rnd_mode   = rnd_mode;
    item.operands[0] = fma_operand_utils::one();
    item.operands[1] = fma_operand_utils::one();
    item.operands[2] = fma_operand_utils::positive_zero();
    item.is_boxed    = 3'b111;
    item.tag         = 8'h00;
    item.mask        = 1'b0;
    item.aux         = 8'h00;
    return item;
  endfunction

  virtual task body();
  endtask
endclass

`endif

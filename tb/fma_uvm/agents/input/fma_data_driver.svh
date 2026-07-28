// SPDX-License-Identifier: SHL-0.51
`ifndef FMA_DATA_DRIVER_SVH
`define FMA_DATA_DRIVER_SVH

class fma_data_driver extends uvm_driver #(fma_operation_item, fma_data_response);
  `uvm_component_utils(fma_data_driver)

  fma_input_agent_cfg cfg;

  function new(string name = "fma_data_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(fma_input_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("FMA_INPUT_CFG", "fma_input_agent_cfg was not configured")
    end
    if (cfg.vif == null) begin
      `uvm_fatal("FMA_INPUT_VIF", "fma_input_agent_cfg.vif is null")
    end
  endfunction

  task run_phase(uvm_phase phase);
    fma_operation_item   req;
    fma_data_response   rsp;
    fma_data_completion_e completion;
    bit already_at_negedge;

    // Safe values are established independently of sequence start time. Only
    // this driver writes the operation fields and in_valid_i.
    cfg.vif.operands_i <= '0;
    cfg.vif.is_boxed_i <= '0;
    cfg.vif.rnd_mode_i <= fpnew_pkg::RNE;
    cfg.vif.op_i       <= fpnew_pkg::FMADD;
    cfg.vif.op_mod_i   <= 1'b0;
    cfg.vif.tag_i      <= '0;
    cfg.vif.mask_i     <= 1'b0;
    cfg.vif.aux_i      <= '0;
    cfg.vif.in_valid_i <= 1'b0;
    already_at_negedge = 1'b0;

    forever begin
      req = null;

      // Polling with try_next_item is intentional: no sequence item is taken
      // while reset is active or while flush is asserted.
      while (req == null) begin
        if (!already_at_negedge) begin
          @(cfg.vif.data_drv_cb);
        end
        already_at_negedge = 1'b0;
        if ((cfg.vif.rst_ni === 1'b1) && (cfg.vif.flush_i === 1'b0)) begin
          seq_item_port.try_next_item(req);
        end
      end

      drive_request(req);
      wait_for_completion(completion);

      req.completion = completion;
      rsp = fma_data_response::type_id::create("rsp");
      rsp.set_id_info(req);
      rsp.completion = completion;
      // Completing at the sampling edge gives the sequence half a cycle to
      // provide the next item, allowing back-to-back accepted operations.
      seq_item_port.item_done(rsp);

      if (completion == FMA_DATA_ACCEPTED) begin
        @(cfg.vif.data_drv_cb);
        cfg.vif.data_drv_cb.in_valid_i <= 1'b0;
        already_at_negedge = 1'b1;
      end else begin
        // Async reset can cancel between clock edges. A synchronous flush is
        // detected at its sampling edge. In either case, withdraw the canceled
        // item immediately after detection and never retry it automatically.
        cfg.vif.in_valid_i <= 1'b0;
        already_at_negedge = 1'b0;
      end
    end
  endtask

  task drive_request(fma_operation_item req);
    cfg.vif.data_drv_cb.operands_i <= {
      req.operands[2], req.operands[1], req.operands[0]
    };
    cfg.vif.data_drv_cb.is_boxed_i <= req.is_boxed;
    cfg.vif.data_drv_cb.rnd_mode_i <= req.rnd_mode;
    cfg.vif.data_drv_cb.op_i       <= req.op_i;
    cfg.vif.data_drv_cb.op_mod_i   <= req.op_mod_i;
    cfg.vif.data_drv_cb.tag_i      <= req.tag;
    cfg.vif.data_drv_cb.mask_i     <= req.mask;
    cfg.vif.data_drv_cb.aux_i      <= req.aux;
    cfg.vif.data_drv_cb.in_valid_i <= 1'b1;
  endtask

  task wait_for_completion(output fma_data_completion_e completion);
    bit completed;

    forever begin
      completed = 1'b0;
      fork : completion_waiters
        begin : sample_handshake
          @(posedge cfg.vif.clk_i);
          if (cfg.vif.rst_ni !== 1'b1) begin
            completion = FMA_DATA_CANCELED_BY_RESET;
            completed = 1'b1;
          end else if (cfg.vif.flush_i === 1'b1) begin
            completion = FMA_DATA_CANCELED_BY_FLUSH;
            completed = 1'b1;
          end else if ((cfg.vif.in_valid_i === 1'b1) &&
                       (cfg.vif.in_ready_o === 1'b1)) begin
            completion = FMA_DATA_ACCEPTED;
            completed = 1'b1;
          end
        end
        begin : observe_reset
          @(negedge cfg.vif.rst_ni);
          completion = FMA_DATA_CANCELED_BY_RESET;
          completed = 1'b1;
        end
      join_any
      disable completion_waiters;
      if (completed) begin
        return;
      end
    end
  endtask
endclass

`endif

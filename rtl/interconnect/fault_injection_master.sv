// fault_injection_master.sv
// MINERVA P4/P5 - Fault-injection master.
//
// Same shape as dma_engine.sv: an AXI4-Lite slave port for programming
// (exposed at system top level, like dma_reg, so the CPU or a host/JTAG
// agent can drive a fault campaign), and an AXI4-Lite master port that
// reuses axi4lite_master_engine for the actual bus access. The master
// port plugs into axi4lite_crossbar as Master 1, so it can reach any
// slave (mem, dma_reg, periph) through the same arbitrated fabric as
// riscv_cpu_p3's ext_mem -- exercising real contention against the CPU
// path, not a separate side-channel.
//
// Register map (offsets, word-addressed slave, 32-bit regs):
//   0x00 TARGET_ADDR  RW   address to inject fault at
//   0x04 INJECT_DATA  RW   value written directly in MODE 0
//   0x08 INJECT_MASK  RW   XOR mask applied to read data in MODE 1
//   0x0C CTRL         W1P  bit0 = START (self-clears)
//                          bit1 = MODE  (0 = stuck-at overwrite,
//                                        1 = read-modify-XOR bit-flip)
//   0x10 STATUS       RO   bit0 = BUSY, bit1 = DONE (W1C via STATUS write),
//                          bit2 = ERROR (SLVERR/DECERR seen on target)

`include "axi4lite_ports.vh"

module fault_injection_master (
    input  logic clk,
    input  logic rst_n,

    // Programming slave port (CPU or host/JTOAG agent drives this)
    `AXI4LITE_SLAVE_PORTS(s_axi),

    // Fault-injection master port -> plugs into crossbar as Master 1
    `AXI4LITE_MASTER_PORTS(m_axi),

    output logic irq   // pulses on DONE, mirrors dma_engine's irq
);

  // ---------------- Registers ----------------
  logic [31:0] target_addr_q, inject_data_q, inject_mask_q;
  logic        busy_q, done_q, error_q, mode_q;
  logic        start_pulse;
  logic        done_clr_pulse;

  // ---------------- AXI4-Lite slave (register access) ----------------
  // Identical single-outstanding slave shape to dma_engine.sv's s_axi.
  typedef enum logic [1:0] {SLV_IDLE, SLV_WRITE, SLV_READ, SLV_BRESP} slv_state_e;
  slv_state_e slv_q;

  logic [31:0] awaddr_q, araddr_q;

  assign s_axi_awready = (slv_q == SLV_IDLE);
  assign s_axi_wready  = (slv_q == SLV_IDLE) || (slv_q == SLV_WRITE);
  assign s_axi_arready = (slv_q == SLV_IDLE);
  assign s_axi_bresp   = 2'b00;
  assign s_axi_rresp   = 2'b00;

  logic bvalid_q, rvalid_q;
  logic [31:0] rdata_q;
  assign s_axi_bvalid = bvalid_q;
  assign s_axi_rvalid = rvalid_q;
  assign s_axi_rdata  = rdata_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      slv_q          <= SLV_IDLE;
      target_addr_q  <= '0;
      inject_data_q  <= '0;
      inject_mask_q  <= '0;
      mode_q         <= 1'b0;
      bvalid_q       <= 1'b0;
      rvalid_q       <= 1'b0;
      rdata_q        <= '0;
      start_pulse    <= 1'b0;
      done_clr_pulse <= 1'b0;
    end else begin
      start_pulse    <= 1'b0;
      done_clr_pulse <= 1'b0;
      if (bvalid_q && s_axi_bready) bvalid_q <= 1'b0;
      if (rvalid_q && s_axi_rready) rvalid_q <= 1'b0;

      unique case (slv_q)
        SLV_IDLE: begin
          if (s_axi_awvalid && s_axi_wvalid) begin
            awaddr_q <= s_axi_awaddr;
            unique case (s_axi_awaddr[7:0])
              8'h00: target_addr_q <= s_axi_wdata;
              8'h04: inject_data_q <= s_axi_wdata;
              8'h08: inject_mask_q <= s_axi_wdata;
              8'h0C: begin
                if (s_axi_wdata[0] && !busy_q) start_pulse <= 1'b1;
                mode_q <= s_axi_wdata[1];
              end
              8'h10: if (s_axi_wdata[1]) done_clr_pulse <= 1'b1; // W1C DONE
              default: ;
            endcase
            bvalid_q <= 1'b1;
            slv_q    <= SLV_BRESP;
          end else if (s_axi_arvalid) begin
            araddr_q <= s_axi_araddr;
            unique case (s_axi_araddr[7:0])
              8'h00: rdata_q <= target_addr_q;
              8'h04: rdata_q <= inject_data_q;
              8'h08: rdata_q <= inject_mask_q;
              8'h10: rdata_q <= {29'd0, error_q, done_q, busy_q};
              default: rdata_q <= 32'd0;
            endcase
            rvalid_q <= 1'b1;
            slv_q    <= SLV_IDLE;
          end
        end
        SLV_BRESP: begin
          if (!bvalid_q) slv_q <= SLV_IDLE; // wait for bready to clear it
        end
        default: slv_q <= SLV_IDLE;
      endcase
    end
  end

  // ---------------- Injection engine (master side) ----------------
  logic        axi_req_valid, axi_req_ready, axi_req_we;
  logic [31:0] axi_req_addr, axi_req_wdata;
  logic [3:0]  axi_req_be;
  logic        axi_rdata_valid, axi_bresp_valid, axi_resp_err;
  logic [31:0] axi_rdata;

  axi4lite_master_engine u_axi_eng (
      .clk         (clk),
      .rst_n       (rst_n),
      .req_valid   (axi_req_valid),
      .req_ready   (axi_req_ready),
      .req_addr    (axi_req_addr),
      .req_wdata   (axi_req_wdata),
      .req_be      (axi_req_be),
      .req_we      (axi_req_we),
      .rdata_valid (axi_rdata_valid),
      .rdata       (axi_rdata),
      .bresp_valid (axi_bresp_valid),
      .resp_err    (axi_resp_err),
      .m_axi_awaddr (m_axi_awaddr),   .m_axi_awvalid(m_axi_awvalid), .m_axi_awready(m_axi_awready),
      .m_axi_wdata  (m_axi_wdata),    .m_axi_wstrb  (m_axi_wstrb),   .m_axi_wvalid (m_axi_wvalid), .m_axi_wready(m_axi_wready),
      .m_axi_bresp  (m_axi_bresp),    .m_axi_bvalid (m_axi_bvalid),  .m_axi_bready (m_axi_bready),
      .m_axi_araddr (m_axi_araddr),   .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
      .m_axi_rdata  (m_axi_rdata),    .m_axi_rresp  (m_axi_rresp),   .m_axi_rvalid (m_axi_rvalid), .m_axi_rready(m_axi_rready)
  );

  // FI_IDLE -> (MODE 0) FI_WRITE -> FI_DONE
  //         -> (MODE 1) FI_READ  -> FI_WRITE -> FI_DONE
  typedef enum logic [2:0] {FI_IDLE, FI_READ, FI_WRITE, FI_DONE} fi_state_e;
  fi_state_e fi_q;

  logic [31:0] hold_data_q;   // holds read value between READ and WRITE in MODE 1

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fi_q          <= FI_IDLE;
      busy_q        <= 1'b0;
      done_q        <= 1'b0;
      error_q       <= 1'b0;
      irq           <= 1'b0;
      hold_data_q   <= '0;
      axi_req_valid <= 1'b0;
    end else begin
      irq           <= 1'b0;
      axi_req_valid <= 1'b0;
      if (done_clr_pulse) done_q <= 1'b0;

      unique case (fi_q)
        FI_IDLE: begin
          if (start_pulse) begin
            busy_q  <= 1'b1;
            error_q <= 1'b0;
            fi_q    <= mode_q ? FI_READ : FI_WRITE;
          end
        end

        // MODE 1 only: read current value at TARGET_ADDR so it can be
        // XOR'd with INJECT_MASK before writing back.
        FI_READ: begin
          if (axi_req_ready && !axi_rdata_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b0;
            axi_req_addr  <= target_addr_q;
          end
          if (axi_rdata_valid) begin
            hold_data_q <= axi_rdata;
            error_q     <= error_q | axi_resp_err;
            fi_q        <= FI_WRITE;
          end
        end

        // MODE 0: write INJECT_DATA directly (stuck-at).
        // MODE 1: write hold_data_q ^ INJECT_MASK (bit-flip).
        FI_WRITE: begin
          if (axi_req_ready && !axi_bresp_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b1;
            axi_req_addr  <= target_addr_q;
            axi_req_wdata <= mode_q ? (hold_data_q ^ inject_mask_q) : inject_data_q;
            axi_req_be    <= 4'hF;
          end
          if (axi_bresp_valid) begin
            error_q <= error_q | axi_resp_err;
            fi_q    <= FI_DONE;
          end
        end

        FI_DONE: begin
          busy_q <= 1'b0;
          done_q <= 1'b1;
          irq    <= 1'b1;
          fi_q   <= FI_IDLE;
        end

        default: fi_q <= FI_IDLE;
      endcase
    end
  end

endmodule : fault_injection_master

        
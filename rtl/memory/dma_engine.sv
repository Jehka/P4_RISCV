// dma_engine.sv
// MINERVA P3 - Single-channel DMA engine.
// Slave side: CPU programs registers over AXI4-Lite (addr map below).
// Master side: reuses axi4lite_master_engine for the actual transfer,
// word-at-a-time (AXI4-Lite has no burst).
//
// Register map (offsets, word-addressed slave, 32-bit regs):
//   0x00 SRC_ADDR   RW
//   0x04 DST_ADDR   RW
//   0x08 LENGTH     RW   (bytes, must be multiple of 4)
//   0x0C CTRL       W1P  bit0 = START (self-clears)
//   0x10 STATUS     RO   bit0 = BUSY, bit1 = DONE (W1C via STATUS write), bit2 = ERROR

`include "axi4lite_ports.vh"

module dma_engine (
    input  logic clk,
    input  logic rst_n,

    // CPU-programming slave port
    `AXI4LITE_SLAVE_PORTS(s_axi),

    // Transfer master port
    `AXI4LITE_MASTER_PORTS(m_axi),

    output logic irq
);

  // ---------------- Registers ----------------
  logic [31:0] src_addr_q, dst_addr_q, length_q;
  logic        busy_q, done_q, error_q;
  logic        start_pulse;
  logic        done_clr_pulse;

  // ---------------- AXI4-Lite slave (register access) ----------------
  // Minimal single-outstanding slave: accepts one write or one read at a time.
  typedef enum logic [1:0] {SLV_IDLE, SLV_WRITE, SLV_READ, SLV_BRESP} slv_state_e;
  slv_state_e slv_q;

  logic [31:0] awaddr_q, araddr_q, wdata_q;

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
      slv_q       <= SLV_IDLE;
      src_addr_q  <= '0;
      dst_addr_q  <= '0;
      length_q    <= '0;
      bvalid_q    <= 1'b0;
      rvalid_q    <= 1'b0;
      rdata_q     <= '0;
      start_pulse    <= 1'b0;
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
              8'h00: src_addr_q <= s_axi_wdata;
              8'h04: dst_addr_q <= s_axi_wdata;
              8'h08: length_q   <= s_axi_wdata;
              8'h0C: if (s_axi_wdata[0] && !busy_q) start_pulse <= 1'b1;
              8'h10: if (s_axi_wdata[1]) done_clr_pulse <= 1'b1; // W1C DONE
              default: ;
            endcase
            bvalid_q <= 1'b1;
            slv_q    <= SLV_BRESP;
          end else if (s_axi_arvalid) begin
            araddr_q <= s_axi_araddr;
            unique case (s_axi_araddr[7:0])
              8'h00: rdata_q <= src_addr_q;
              8'h04: rdata_q <= dst_addr_q;
              8'h08: rdata_q <= length_q;
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

  // ---------------- Transfer engine (master side) ----------------
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

  typedef enum logic [1:0] {DMA_IDLE, DMA_READ, DMA_WRITE, DMA_DONE} dma_state_e;
  dma_state_e dma_q;

  logic [31:0] cur_src_q, cur_dst_q, remain_q;
  logic [31:0] hold_data_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dma_q      <= DMA_IDLE;
      busy_q     <= 1'b0;
      done_q     <= 1'b0;
      error_q    <= 1'b0;
      irq        <= 1'b0;
      cur_src_q  <= '0;
      cur_dst_q  <= '0;
      remain_q   <= '0;
      axi_req_valid <= 1'b0;
    end else begin
      irq <= 1'b0;
      axi_req_valid <= 1'b0;
      if (done_clr_pulse) done_q <= 1'b0;

      unique case (dma_q)
        DMA_IDLE: begin
          if (start_pulse) begin
            cur_src_q <= src_addr_q;
            cur_dst_q <= dst_addr_q;
            remain_q  <= length_q;
            busy_q    <= 1'b1;
            error_q   <= 1'b0;
            dma_q     <= (length_q != 0) ? DMA_READ : DMA_DONE;
          end
        end

        DMA_READ: begin
          if (axi_req_ready && !axi_rdata_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b0;
            axi_req_addr  <= cur_src_q;
          end
          if (axi_rdata_valid) begin
            hold_data_q <= axi_rdata;
            error_q     <= error_q | axi_resp_err;
            dma_q       <= DMA_WRITE;
          end
        end

        DMA_WRITE: begin
          if (axi_req_ready && !axi_bresp_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b1;
            axi_req_addr  <= cur_dst_q;
            axi_req_wdata <= hold_data_q;
            axi_req_be    <= 4'hF;
          end
          if (axi_bresp_valid) begin
            error_q  <= error_q | axi_resp_err;
            cur_src_q <= cur_src_q + 32'd4;
            cur_dst_q <= cur_dst_q + 32'd4;
            if (remain_q <= 32'd4) begin
              remain_q <= 32'd0;
              dma_q    <= DMA_DONE;
            end else begin
              remain_q <= remain_q - 32'd4;
              dma_q    <= DMA_READ;
            end
          end
        end

        DMA_DONE: begin
          busy_q <= 1'b0;
          done_q <= 1'b1;
          irq    <= 1'b1;
          dma_q  <= DMA_IDLE;
        end

        default: dma_q <= DMA_IDLE;
      endcase
    end
  end

endmodule : dma_engine
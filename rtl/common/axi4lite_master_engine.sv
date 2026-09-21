// axi4lite_master_engine.sv
// Shared AXI4-Lite master FSM. Both cache_controller (on miss/writeback) and
// dma_engine (on transfer) instantiate this instead of hand-rolling AXI
// handshakes twice. Single point of AXI-protocol truth for P3.
//
// Local-side contract (simple valid/ready, one outstanding txn):
//   req_valid   : pulse high with addr/wdata/we/be to start a txn
//   req_ready   : engine can accept a new request
//   rdata_valid : one-cycle pulse, rdata holds read result (we=0 txns)
//   bresp_valid : one-cycle pulse, write txn completed (we=1 txns)
//   resp_err    : SLVERR/DECERR seen on completed txn (sticky for that txn)

`include "axi4lite_ports.vh"

module axi4lite_master_engine (
    input  logic        clk,
    input  logic        rst_n,

    // local simple bus
    input  logic         req_valid,
    output logic         req_ready,
    input  logic [31:0]  req_addr,
    input  logic [31:0]  req_wdata,
    input  logic [3:0]   req_be,
    input  logic         req_we,      // 1 = write, 0 = read

    output logic         rdata_valid,
    output logic [31:0]  rdata,
    output logic         bresp_valid,
    output logic         resp_err,

    // AXI4-Lite master
    `AXI4LITE_MASTER_PORTS(m_axi)
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_AR,        // address-read outstanding
    S_R,         // waiting for read data
    S_AW_W,      // address-write + write-data outstanding (issued together)
    S_B          // waiting for write response
  } state_e;

  state_e state_q, state_d;

  logic [31:0] addr_q, wdata_q;
  logic [3:0]  be_q;

  assign req_ready = (state_q == S_IDLE);

  // AR channel
  assign m_axi_araddr  = addr_q;
  assign m_axi_arvalid = (state_q == S_AR);
  assign m_axi_rready  = (state_q == S_R);

  // AW/W channel (issued in same cycle, held until each ready fires independently)
  assign m_axi_awaddr  = addr_q;
  assign m_axi_wdata   = wdata_q;
  assign m_axi_wstrb   = be_q;
  assign m_axi_bready  = (state_q == S_B);

  logic awvalid_q, wvalid_q;
  assign m_axi_awvalid = awvalid_q;
  assign m_axi_wvalid  = wvalid_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q     <= S_IDLE;
      addr_q      <= '0;
      wdata_q     <= '0;
      be_q        <= '0;
      awvalid_q   <= 1'b0;
      wvalid_q    <= 1'b0;
      rdata_valid <= 1'b0;
      rdata       <= '0;
      bresp_valid <= 1'b0;
      resp_err    <= 1'b0;
    end else begin
      rdata_valid <= 1'b0;
      bresp_valid <= 1'b0;

      unique case (state_q)
        S_IDLE: begin
          if (req_valid) begin
            addr_q  <= req_addr;
            wdata_q <= req_wdata;
            be_q    <= req_be;
            if (req_we) begin
              awvalid_q <= 1'b1;
              wvalid_q  <= 1'b1;
              state_q   <= S_AW_W;
            end else begin
              state_q   <= S_AR;
            end
          end
        end

        S_AR: begin
          if (m_axi_arready) state_q <= S_R;
        end

        S_R: begin
          if (m_axi_rvalid) begin
            rdata       <= m_axi_rdata;
            rdata_valid <= 1'b1;
            resp_err    <= (m_axi_rresp != 2'b00);
            state_q     <= S_IDLE;
          end
        end

        S_AW_W: begin
          if (m_axi_awready) awvalid_q <= 1'b0;
          if (m_axi_wready)  wvalid_q  <= 1'b0;
          if ((m_axi_awready || !awvalid_q) && (m_axi_wready || !wvalid_q))
            state_q <= S_B;
        end

        S_B: begin
          if (m_axi_bvalid) begin
            bresp_valid <= 1'b1;
            resp_err    <= (m_axi_bresp != 2'b00);
            state_q     <= S_IDLE;
          end
        end

        default: state_q <= S_IDLE;
      endcase
    end
  end

endmodule : axi4lite_master_engine
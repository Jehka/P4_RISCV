// cache_dma_arbiter.sv
// MINERVA P3 - Round-robin arbiter between cache_controller and dma_engine
// memory-side AXI4-Lite masters, muxed onto one shared AXI4-Lite port to
// external memory. Same round-robin-with-held-grant principle as P1's
// rr_arbiter.sv; reused here as the P1->P3 continuity IP, and again as the
// base arbitration scheme inside the P4 crossbar.
//
// Grant is held for the full duration of a transaction (AW/W...B or AR...R)
// so neither master's outstanding txn is torn mid-flight; priority rotates
// to the other requester only after the current txn fully completes.

`include "axi4lite_ports.vh"

module cache_dma_arbiter (
    input  logic clk,
    input  logic rst_n,

    // Requester 0: cache controller (higher default priority on tie)
    `AXI4LITE_SLAVE_PORTS(cache),
    // Requester 1: DMA engine
    `AXI4LITE_SLAVE_PORTS(dma),

    // Shared upstream master port to memory
    `AXI4LITE_MASTER_PORTS(mem)
);

  // A requester is "active" if it has an outstanding AW/AR handshake pending
  // or is mid-transaction. We track via simple request-detect on AW/AR valid.
  wire cache_req = cache_awvalid || cache_arvalid;
  wire dma_req   = dma_awvalid   || dma_arvalid;

  typedef enum logic [1:0] {ARB_IDLE, GRANT_CACHE, GRANT_DMA} arb_state_e;
  arb_state_e state_q;
  logic       last_grant_dma_q; // rotates priority on tie

  // txn-in-flight tracking per grantee so we hold grant until B or R fires
  wire cache_txn_done = (cache_bvalid && cache_bready) || (cache_rvalid && cache_rready);
  wire dma_txn_done   = (dma_bvalid && dma_bready)     || (dma_rvalid && dma_rready);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q          <= ARB_IDLE;
      last_grant_dma_q <= 1'b0;
    end else begin
      unique case (state_q)
        ARB_IDLE: begin
          if (cache_req && dma_req) begin
            // tie: rotate
            if (last_grant_dma_q) begin
              state_q          <= GRANT_CACHE;
              last_grant_dma_q <= 1'b0;
            end else begin
              state_q          <= GRANT_DMA;
              last_grant_dma_q <= 1'b1;
            end
          end else if (cache_req) begin
            state_q          <= GRANT_CACHE;
            last_grant_dma_q <= 1'b0;
          end else if (dma_req) begin
            state_q          <= GRANT_DMA;
            last_grant_dma_q <= 1'b1;
          end
        end

        GRANT_CACHE: if (cache_txn_done) state_q <= ARB_IDLE;
        GRANT_DMA:   if (dma_txn_done)   state_q <= ARB_IDLE;

        default: state_q <= ARB_IDLE;
      endcase
    end
  end

  wire grant_cache = (state_q == GRANT_CACHE);
  wire grant_dma   = (state_q == GRANT_DMA);

  // ---------------- Mux: cache <-> mem when granted ----------------
  assign mem_awaddr  = grant_cache ? cache_awaddr  : dma_awaddr;
  assign mem_awvalid = grant_cache ? cache_awvalid : (grant_dma ? dma_awvalid : 1'b0);
  assign mem_wdata   = grant_cache ? cache_wdata   : dma_wdata;
  assign mem_wstrb   = grant_cache ? cache_wstrb   : dma_wstrb;
  assign mem_wvalid  = grant_cache ? cache_wvalid  : (grant_dma ? dma_wvalid : 1'b0);
  assign mem_bready  = grant_cache ? cache_bready  : (grant_dma ? dma_bready : 1'b0);
  assign mem_araddr  = grant_cache ? cache_araddr  : dma_araddr;
  assign mem_arvalid = grant_cache ? cache_arvalid : (grant_dma ? dma_arvalid : 1'b0);
  assign mem_rready  = grant_cache ? cache_rready  : (grant_dma ? dma_rready : 1'b0);

  assign cache_awready = grant_cache ? mem_awready : 1'b0;
  assign cache_wready  = grant_cache ? mem_wready  : 1'b0;
  assign cache_bresp   = mem_bresp;
  assign cache_bvalid  = grant_cache ? mem_bvalid  : 1'b0;
  assign cache_arready = grant_cache ? mem_arready : 1'b0;
  assign cache_rdata   = mem_rdata;
  assign cache_rresp   = mem_rresp;
  assign cache_rvalid  = grant_cache ? mem_rvalid  : 1'b0;

  assign dma_awready = grant_dma ? mem_awready : 1'b0;
  assign dma_wready  = grant_dma ? mem_wready  : 1'b0;
  assign dma_bresp   = mem_bresp;
  assign dma_bvalid  = grant_dma ? mem_bvalid  : 1'b0;
  assign dma_arready = grant_dma ? mem_arready : 1'b0;
  assign dma_rdata   = mem_rdata;
  assign dma_rresp   = mem_rresp;
  assign dma_rvalid  = grant_dma ? mem_rvalid  : 1'b0;

endmodule : cache_dma_arbiter
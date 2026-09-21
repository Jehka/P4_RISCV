// cache_controller_bram_v2.sv
// MINERVA P4.5 - L1 Cache Controller.
//   v1: data_array moved to BRAM (see BRAM note below)
//   v2: tag comparison REGISTERED (this file)
//
// ============ v2 CHANGE: REGISTERED TAG COMPARE ============
// After the BRAM fix, the critical path was consistently:
//     req_addr_q -> tag compare (CARRY4 x2) -> hit -> state_q
//       -> dirty_array[n]/D
// 12-13 logic levels, ~73% route delay. It was the limiter across three
// consecutive builds, and closure was only ever reached by post-route
// phys opt scraping to +0.045 ns (2025.1) and +0.002 ns (2025.2) -- i.e.
// margin small enough that any change, or any tool version, breaks it.
//
// The cause: 'hit' is combinational over tag_array + valid_array, and it
// feeds the FSM AND the dirty/valid updates in the same cycle.
//
// Fix: a dedicated TAG_LOOKUP cycle. tag/valid/dirty are read and the
// comparison registered into hit_q / valid_q_r / dirty_q_r; the FSM then
// decides from those registers the following cycle. The long combinational
// chain now ends at a flop instead of continuing into the state machine.
//
// NOTE ON LATENCY -- this costs nothing:
// TAG_LOOKUP also issues the data_array read for {req_index, req_word},
// so the hit data is already in data_rdata_q when TAG_CHECK runs. That
// makes the v1 READ_DATA state redundant and it is removed. A read hit
// is still IDLE -> TAG_LOOKUP -> TAG_CHECK, exactly as it was
// IDLE -> TAG_CHECK -> READ_DATA before.
//
// Functionally identical to cache_controller.sv (direct-mapped, 4KB,
// 16B lines, write-back / write-allocate, blocking). The ONLY change is
// how data_array is implemented, plus the FSM states needed to tolerate
// the resulting read latency.
//
// ================== WHY THIS EXISTS ==================
// In cache_controller.sv, data_array lives inside
//     always_ff @(posedge clk or negedge rst_n)
// Vivado will not infer BRAM for a memory in a reset-sensitive block --
// Xilinx block RAM has no asynchronous reset. It therefore built the
// array out of flip-flops:
//
//   WARNING [Synth 8-11357] ... data_array_reg with 32768 registers
//   WARNING [Synth 8-4767]  RAM "tag_array_reg" dissolved into registers
//                           Reason: RAM is sensitive to asynchronous reset
//
// Measured consequence on the P4 design (7z020, 100 MHz):
//   256 lines: 80591 endpoints, 42575 failing, WNS -4.316 ns
//    64 lines: 28449 endpoints,  7619 failing, WNS -2.866 ns
// i.e. the cache was ~2/3 of every register in the design, and the
// critical path was req_addr_q -> tag compare -> hit -> data_array CE,
// 78% of which was ROUTE delay caused by hit fanning out to hundreds of
// CE pins spread across the die.
//
// ================== WHAT CHANGED ==================
// 1. data_array moved to its own always_ff @(posedge clk) with NO reset.
//    Contents are undefined at power-up, which is correct and safe:
//    valid_array (which KEEPS its reset) is what makes the cache return
//    only real data. Never reading unwritten lines is a property of the
//    valid bits, not of the data being zeroed.
//
// 2. Single registered read port. The original read data_array from two
//    states with different addresses (TAG_CHECK used req_word,
//    WRITEBACK used beat_cnt_q). Those states are mutually exclusive, so
//    one port suffices -- but the address must now be muxed explicitly
//    so synthesis can see it is a single port.
//
// 3. Registered reads cost one cycle. The original TAG_CHECK read the
//    array and answered the CPU in the same cycle; WRITEBACK likewise
//    used the data combinationally. Two states are added to absorb that
//    latency:
//        TAG_CHECK  -> issue read address, evaluate hit
//        READ_DATA  -> data valid this cycle, answer the CPU
//        WB_READ    -> issue read address for the beat
//        WRITEBACK  -> data valid, issue the AXI write
//    Write hits do NOT need the extra cycle (no read involved), so they
//    still complete out of TAG_CHECK directly.
//
// 4. tag_array left as-is. It is 256x20 -- small enough that distributed
//    RAM is fine -- and 'hit' must read it combinationally to keep the
//    hit/miss decision in one cycle. Forcing it to BRAM would add
//    latency to every access for little area gain.
//
// ================== VERIFY BEFORE TRUSTING ==================
// This edits code that was hardware-verified in P3. Re-run tb_p3_top and
// tb_concurrent_stress before synthesising. The tests that matter most:
// T1/T2 (miss->allocate->hit), T3 (write hit), T4 (dirty eviction and
// re-fetch -- this is the one that exercises the new WB_READ path).

`include "axi4lite_ports.vh"

`timescale 1ns/1ps

module cache_controller (
    input  logic        clk,
    input  logic        rst_n,

    // CPU side (simple bus, from P2 MEM stage)
    input  logic         cpu_req_valid,
    output logic         cpu_req_ready,
    input  logic [31:0]  cpu_req_addr,
    input  logic [31:0]  cpu_req_wdata,
    input  logic [3:0]   cpu_req_be,
    input  logic         cpu_req_we,

    output logic         cpu_resp_valid,
    output logic [31:0]  cpu_resp_rdata,

    // Memory side
    `AXI4LITE_MASTER_PORTS(m_axi)
);

  localparam int INDEX_BITS  = 8;
  localparam int OFFSET_BITS = 2;   // word select within line (4 words)
  localparam int NUM_LINES   = 1 << INDEX_BITS;
  localparam int TAG_BITS    = 32 - INDEX_BITS - OFFSET_BITS - 2;

  // ---------------- Tag / valid / dirty (small, keep in flops) --------
  logic [TAG_BITS-1:0] tag_array   [NUM_LINES];
  logic                valid_array [NUM_LINES];
  logic                dirty_array [NUM_LINES];

  // ---------------- Data array: BRAM-inferring ------------------------
  // Flattened to [NUM_LINES*4] with a single {index, word} address so it
  // presents as one ordinary single-port memory. The 2-D form
  // ([NUM_LINES][4]) also infers, but flattening makes the single-port
  // intent unambiguous to synthesis.
  localparam int DATA_DEPTH = NUM_LINES * 4;
  localparam int DATA_AW    = INDEX_BITS + 2;

  (* ram_style = "block" *)
  logic [31:0] data_array [DATA_DEPTH];

  logic [DATA_AW-1:0] data_addr;      // read/write address (muxed)
  logic [31:0]        data_wdata;
  logic [3:0]         data_wbe;
  logic               data_we;
  logic [31:0]        data_rdata_q;   // registered read output

  // Sole access point to data_array. No reset -- that is the whole point.
  always_ff @(posedge clk) begin
    if (data_we) begin
      for (int b = 0; b < 4; b++)
        if (data_wbe[b])
          data_array[data_addr][b*8 +: 8] <= data_wdata[b*8 +: 8];
    end
    data_rdata_q <= data_array[data_addr];
  end

  // ---------------- Address decode (registered request) ---------------
  logic [31:0] req_addr_q, req_wdata_q;
  logic [3:0]  req_be_q;
  logic        req_we_q;

  // NOTE: these slices are derived from the parameters rather than
  // hardcoded. The original used [31:12] and [11:4], which silently
  // disagreed with INDEX_BITS if it was ever changed -- a latent bug
  // found while shrinking the cache for the timing experiment.
  wire [TAG_BITS-1:0]   req_tag   = req_addr_q[31 -: TAG_BITS];
  wire [INDEX_BITS-1:0] req_index = req_addr_q[INDEX_BITS+OFFSET_BITS+1 -: INDEX_BITS];
  wire [1:0]            req_word  = req_addr_q[3:2];

  // Combinational lookup -- now consumed ONLY by the TAG_LOOKUP register
  // stage below, never directly by the FSM. This is the long path, and it
  // now terminates at a flop.
  wire hit_comb   = valid_array[req_index] && (tag_array[req_index] == req_tag);
  wire valid_comb = valid_array[req_index];
  wire dirty_comb = dirty_array[req_index];

  // Registered versions, valid from TAG_CHECK onwards.
  logic hit_q, valid_q_r, dirty_q_r;

  // ---------------- AXI engine interface ------------------------------
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

  // ---------------- FSM ------------------------------------------------
  typedef enum logic [2:0] {
    IDLE,
    TAG_LOOKUP,  // v2: read tag/valid/dirty and REGISTER the comparison;
                 //     also issue the data_array read for this word
    TAG_CHECK,   // decide from hit_q; data_rdata_q already valid
    WB_READ,     // issue read address for this writeback beat
    WRITEBACK,   // data_rdata_q valid, drive the AXI write
    ALLOCATE     // fill line: 4 sequential AXI reads
  } state_e;

  state_e state_q;
  logic [1:0] beat_cnt_q;

  assign cpu_req_ready = (state_q == IDLE);

  // ---- data_array port control ----
  // Address is muxed by state; the states that read are mutually
  // exclusive, so this stays a single port.
  always_comb begin
    data_we    = 1'b0;
    data_wdata = req_wdata_q;
    data_wbe   = req_be_q;
    data_addr  = {req_index, req_word};

    unique case (state_q)
      TAG_LOOKUP: begin
        // Issue the read for this word speculatively, before the hit
        // result is known. If it turns out to be a miss the data is
        // simply discarded -- costs nothing and removes a whole state
        // from the read-hit path.
        data_addr = {req_index, req_word};
      end

      TAG_CHECK: begin
        // Decisions here use the REGISTERED hit, not the combinational
        // one -- that is the entire point of v2.
        if (hit_q && req_we_q) begin
          data_we = 1'b1;
        end else if (!hit_q && valid_q_r && dirty_q_r) begin
          // heading for writeback: pre-issue beat 0's read address
          data_addr = {req_index, 2'd0};
        end
      end

      WB_READ: begin
        data_addr = {req_index, beat_cnt_q};
      end

      WRITEBACK: begin
        data_addr = {req_index, beat_cnt_q};
      end

      ALLOCATE: begin
        data_addr  = {req_index, beat_cnt_q};
        data_wdata = axi_rdata;
        data_wbe   = 4'hF;
        data_we    = axi_rdata_valid;
      end

      default: ;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q     <= IDLE;
      beat_cnt_q  <= 2'd0;
      hit_q       <= 1'b0;
      valid_q_r   <= 1'b0;
      dirty_q_r   <= 1'b0;
      req_addr_q  <= '0;
      req_wdata_q <= '0;
      req_be_q    <= '0;
      req_we_q    <= 1'b0;
      cpu_resp_valid <= 1'b0;
      cpu_resp_rdata <= '0;
      axi_req_valid  <= 1'b0;
      axi_req_we     <= 1'b0;
      axi_req_addr   <= '0;
      axi_req_wdata  <= '0;
      axi_req_be     <= '0;
      for (int i = 0; i < NUM_LINES; i++) begin
        valid_array[i] <= 1'b0;
        dirty_array[i] <= 1'b0;
      end
      // tag_array and data_array deliberately NOT reset:
      //   data_array -- resetting it blocks BRAM inference (the bug)
      //   tag_array  -- meaningless without valid_array[i], which IS reset
    end else begin
      cpu_resp_valid <= 1'b0;
      axi_req_valid  <= 1'b0;

      unique case (state_q)

        IDLE: begin
          if (cpu_req_valid) begin
            req_addr_q  <= cpu_req_addr;
            req_wdata_q <= cpu_req_wdata;
            req_be_q    <= cpu_req_be;
            req_we_q    <= cpu_req_we;
            state_q     <= TAG_LOOKUP;
          end
        end

        // v2: the long combinational tag compare happens THIS cycle and
        // lands in flops. Nothing downstream depends on it until next
        // cycle, so the path ends here.
        TAG_LOOKUP: begin
          hit_q     <= hit_comb;
          valid_q_r <= valid_comb;
          dirty_q_r <= dirty_comb;
          state_q   <= TAG_CHECK;
        end

        TAG_CHECK: begin
          // All decisions from REGISTERED lookup results.
          if (hit_q) begin
            if (req_we_q) begin
              // write hit: data_we asserted combinationally above, so the
              // write commits this cycle.
              dirty_array[req_index] <= 1'b1;
            end else begin
              // read hit: data_rdata_q already holds the word, because
              // TAG_LOOKUP issued the read a cycle earlier.
              cpu_resp_rdata <= data_rdata_q;
            end
            cpu_resp_valid <= 1'b1;
            state_q <= IDLE;
          end else begin
            beat_cnt_q <= 2'd0;
            if (valid_q_r && dirty_q_r)
              state_q <= WRITEBACK;   // beat 0 address pre-issued above
            else
              state_q <= ALLOCATE;
          end
        end

        WB_READ: begin
          // read address for this beat was issued combinationally;
          // data lands next cycle.
          state_q <= WRITEBACK;
        end

        WRITEBACK: begin
          if (axi_req_ready && !axi_bresp_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b1;
            axi_req_addr  <= {tag_array[req_index], req_index, beat_cnt_q, 2'b00};
            axi_req_wdata <= data_rdata_q;    // registered read data
            axi_req_be    <= 4'hF;
          end
          if (axi_bresp_valid) begin
            if (beat_cnt_q == 2'd3) begin
              dirty_array[req_index] <= 1'b0;
              beat_cnt_q <= 2'd0;
              state_q    <= ALLOCATE;
            end else begin
              beat_cnt_q <= beat_cnt_q + 2'd1;
              state_q    <= WB_READ;   // fetch the next beat's data
            end
          end
        end

        ALLOCATE: begin
          if (axi_req_ready && !axi_rdata_valid) begin
            axi_req_valid <= 1'b1;
            axi_req_we    <= 1'b0;
            axi_req_addr  <= {req_tag, req_index, beat_cnt_q, 2'b00};
          end
          if (axi_rdata_valid) begin
            // the write into data_array is driven combinationally above
            if (beat_cnt_q == 2'd3) begin
              tag_array[req_index]   <= req_tag;
              valid_array[req_index] <= 1'b1;
              dirty_array[req_index] <= 1'b0;
              beat_cnt_q <= 2'd0;
              // Back to TAG_LOOKUP, not TAG_CHECK: the hit registers must
              // be refreshed now that tag/valid have been updated.
              state_q    <= TAG_LOOKUP;
            end else begin
              beat_cnt_q <= beat_cnt_q + 2'd1;
            end
          end
        end

        default: state_q <= IDLE;
      endcase
    end
  end

endmodule : cache_controller

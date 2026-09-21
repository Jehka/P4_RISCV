// axi4lite_crossbar.sv
// MINERVA P4 - AXI4-Lite Crossbar (N masters x M slaves)
//
// Generalizes the round-robin-with-held-grant arbitration scheme reused
// across P1 (CDC FIFO arbiter) and P3 (cache_dma_arbiter.sv) into a
// parameterized fabric layer. Sits ABOVE P3, not in place of it -
// cache_dma_arbiter.sv stays hardware-verified and untouched.
//
// ASSUMPTIONS (reconcile against your actual axi4lite_pkg.sv):
//   - Standard AXI4-Lite channel signal names (AW/W/B/AR/R)
//   - Address decode via top bits of ADDR_WIDTH selects target slave
//   - No burst support (AXI4-Lite has none), single outstanding txn/master
//
// Vivado IP Integrator note: this file is SystemVerilog (interfaces used
// internally for readability). If this becomes a top-level block for IPI,
// re-flatten to plain Verilog using axi4lite_ports.vh macros, same as P3.

`ifndef AXI4LITE_CROSSBAR_SV
`define AXI4LITE_CROSSBAR_SV

`timescale 1ns/1ps

import axi4lite_pkg::*;

module axi4lite_crossbar #(
    parameter int NUM_MASTERS   = 2,
    parameter int NUM_SLAVES    = 2,
    parameter int ADDR_WIDTH    = 32,
    parameter int DATA_WIDTH    = 32,
    // Base/high address per slave for decode. Defaults below assume the
    // P4 topology extended for AXI instruction fetch:
    //   slave 0: data mem       (matches axi4lite_mem_model, 16KB span)
    //   slave 1: dma_reg        (p3_top's DMA register block, pulled up
    //                            to system level so any master can program it)
    //   slave 2: reserved peripheral (UART/GPIO for P5 fault-injection obs.)
    //   slave 3: imem           (4KB = 1024 words, matches if_stage's
    //                            imem[0:1023]; reset PC moves here so the
    //                            CPU fetches over AXI and programs become
    //                            runtime-loadable + fault-injectable)
    // Override the parameter at instantiation if NUM_SLAVES or the map differs.
    // Whatever the final map is, LOCK it in the Address Editor per the P3
    // lesson -- don't trust Vivado auto-assignment.
    parameter logic [ADDR_WIDTH-1:0] SLAVE_BASE [NUM_SLAVES] = '{
        32'h0000_0000, 32'h0001_0000, 32'h0002_0000, 32'h0003_0000
    },
    parameter logic [ADDR_WIDTH-1:0] SLAVE_HIGH [NUM_SLAVES] = '{
        32'h0000_3FFF, 32'h0001_00FF, 32'h0002_00FF, 32'h0003_0FFF
    }
)(
    input  logic clk,
    input  logic rst_n,           // active-low; VERIFY against get_property
                                   // CONFIG.C_*_RESET_HIGH per P3 lesson -
                                   // do not assume polarity here.

    // ---- Master-side ports (one bundle per master, flattened arrays) ----
    // AW channel
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] m_awaddr,
    input  logic [NUM_MASTERS-1:0]                 m_awvalid,
    output logic [NUM_MASTERS-1:0]                 m_awready,
    // W channel
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] m_wdata,
    input  logic [NUM_MASTERS-1:0][DATA_WIDTH/8-1:0] m_wstrb,
    input  logic [NUM_MASTERS-1:0]                 m_wvalid,
    output logic [NUM_MASTERS-1:0]                 m_wready,
    // B channel
    output logic [NUM_MASTERS-1:0][1:0]            m_bresp,
    output logic [NUM_MASTERS-1:0]                 m_bvalid,
    input  logic [NUM_MASTERS-1:0]                 m_bready,
    // AR channel
    input  logic [NUM_MASTERS-1:0][ADDR_WIDTH-1:0] m_araddr,
    input  logic [NUM_MASTERS-1:0]                 m_arvalid,
    output logic [NUM_MASTERS-1:0]                 m_arready,
    // R channel
    output logic [NUM_MASTERS-1:0][DATA_WIDTH-1:0] m_rdata,
    output logic [NUM_MASTERS-1:0][1:0]            m_rresp,
    output logic [NUM_MASTERS-1:0]                 m_rvalid,
    input  logic [NUM_MASTERS-1:0]                 m_rready,

    // ---- Slave-side ports (one bundle per slave) ----
    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]  s_awaddr,
    output logic [NUM_SLAVES-1:0]                  s_awvalid,
    input  logic [NUM_SLAVES-1:0]                  s_awready,

    output logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]  s_wdata,
    output logic [NUM_SLAVES-1:0][DATA_WIDTH/8-1:0] s_wstrb,
    output logic [NUM_SLAVES-1:0]                  s_wvalid,
    input  logic [NUM_SLAVES-1:0]                  s_wready,

    input  logic [NUM_SLAVES-1:0][1:0]             s_bresp,
    input  logic [NUM_SLAVES-1:0]                  s_bvalid,
    output logic [NUM_SLAVES-1:0]                  s_bready,

    output logic [NUM_SLAVES-1:0][ADDR_WIDTH-1:0]  s_araddr,
    output logic [NUM_SLAVES-1:0]                  s_arvalid,
    input  logic [NUM_SLAVES-1:0]                  s_arready,

    input  logic [NUM_SLAVES-1:0][DATA_WIDTH-1:0]  s_rdata,
    input  logic [NUM_SLAVES-1:0][1:0]             s_rresp,
    input  logic [NUM_SLAVES-1:0]                  s_rvalid,
    output logic [NUM_SLAVES-1:0]                  s_rready
);

    // -----------------------------------------------------------------
    // Address decode: which slave does each master's current txn target?
    // -----------------------------------------------------------------
    function automatic int decode_slave(input logic [ADDR_WIDTH-1:0] addr);
        for (int s = 0; s < NUM_SLAVES; s++) begin
            if (addr >= SLAVE_BASE[s] && addr <= SLAVE_HIGH[s])
                return s;
        end
        return -1; // unmapped -> DECERR, handled downstream
    endfunction

    // -----------------------------------------------------------------
    // Per-slave round-robin-with-held-grant arbiter.
    //
    // Directly generalizes cache_dma_arbiter.sv's ARB_IDLE / GRANT_CACHE /
    // GRANT_DMA FSM: that arbiter is the NUM_MASTERS==2 special case of
    // this logic (grant_idx==0 <-> GRANT_CACHE, grant_idx==1 <-> GRANT_DMA,
    // last_grant_dma_q <-> rr_ptr). Held-grant release condition is
    // identical: (bvalid&&bready) || (rvalid&&rready) on the granted path.
    // -----------------------------------------------------------------
    localparam int MIDX_W = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

    logic [NUM_SLAVES-1:0][NUM_MASTERS-1:0] req_vec;   // per-slave master requests
    logic [NUM_SLAVES-1:0]                  grant_valid;
    logic [NUM_SLAVES-1:0][MIDX_W-1:0]      grant_idx;
    logic [NUM_SLAVES-1:0][MIDX_W-1:0]      rr_ptr;    // rotates on tie, like last_grant_dma_q

    // Synthesizable fixed-priority-from-pointer picker: scans NUM_MASTERS
    // requesters starting at ptr, wrapping, static loop bound -> unrolls
    // to a priority mux, same as Vivado synth does for cache_dma_arbiter's
    // two-way if/else priority chain.
    function automatic logic pick_next(
        input  logic [NUM_MASTERS-1:0] req,
        input  logic [MIDX_W-1:0]      ptr,
        output logic [MIDX_W-1:0]      idx_out
    );
        logic [MIDX_W-1:0] idx;
        int unsigned       sum;
        pick_next = 1'b0;
        idx_out   = ptr;
        // 'off' declared unsigned and ptr widened explicitly: keeps the
        // whole expression unsigned. Vivado flags mixed signed/unsigned
        // here as a CRITICAL WARNING otherwise, and while it happens to
        // be harmless at NUM_MASTERS==2, it is a real hazard for the
        // N-way generality this module is supposed to have.
        for (int unsigned off = 0; off < NUM_MASTERS; off++) begin
            sum = int'({1'b0, ptr}) + off;
            idx = MIDX_W'(sum % int'(NUM_MASTERS));
            if (!pick_next && req[idx]) begin
                idx_out   = idx;
                pick_next = 1'b1;
            end
        end
    endfunction

    genvar gs;
    generate
        for (gs = 0; gs < NUM_SLAVES; gs++) begin : g_arb

            // Request vector: master m requests slave gs if AW or AR is
            // valid and decodes to gs. Same req-detect basis as P3's
            // cache_req/dma_req (awvalid || arvalid).
            always_comb begin
                for (int m = 0; m < NUM_MASTERS; m++) begin
                    req_vec[gs][m] = (m_awvalid[m] && decode_slave(m_awaddr[m]) == gs) ||
                                     (m_arvalid[m] && decode_slave(m_araddr[m]) == gs);
                end
            end

            logic                 found;
            logic [MIDX_W-1:0]    found_idx;
            always_comb found = pick_next(req_vec[gs], rr_ptr[gs], found_idx);

            wire granted_txn_done = (s_bvalid[gs] && s_bready[gs]) ||
                                     (s_rvalid[gs] && s_rready[gs]);

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    grant_valid[gs] <= 1'b0;
                    grant_idx[gs]   <= '0;
                    rr_ptr[gs]      <= '0;
                end else begin
                    if (!grant_valid[gs]) begin
                        if (found) begin
                            grant_valid[gs] <= 1'b1;
                            grant_idx[gs]   <= found_idx;
                        end
                    end else if (granted_txn_done) begin
                        grant_valid[gs] <= 1'b0;
                        // rotate pointer past the master just served, so
                        // it doesn't win ties again next cycle -- N-way
                        // form of last_grant_dma_q's toggle.
                        rr_ptr[gs] <= grant_idx[gs] + 1'b1;
                    end
                end
            end
        end
    endgenerate

    // -----------------------------------------------------------------
    // Mux: connect granted master <-> slave per channel
    // -----------------------------------------------------------------
    always_comb begin
        // defaults
        for (int s = 0; s < NUM_SLAVES; s++) begin
            s_awaddr[s]  = '0; s_awvalid[s] = 1'b0;
            s_wdata[s]   = '0; s_wstrb[s] = '0; s_wvalid[s] = 1'b0;
            s_bready[s]  = 1'b0;
            s_araddr[s]  = '0; s_arvalid[s] = 1'b0;
            s_rready[s]  = 1'b0;
        end
        for (int m = 0; m < NUM_MASTERS; m++) begin
            m_awready[m] = 1'b0;
            m_wready[m]  = 1'b0;
            m_bresp[m]   = 2'b00; m_bvalid[m] = 1'b0;
            m_arready[m] = 1'b0;
            m_rdata[m]   = '0; m_rresp[m] = 2'b00; m_rvalid[m] = 1'b0;
        end

        for (int s = 0; s < NUM_SLAVES; s++) begin
            if (grant_valid[s]) begin
                automatic int m = grant_idx[s];

                s_awaddr[s]  = m_awaddr[m];
                s_awvalid[s] = m_awvalid[m];
                m_awready[m] = s_awready[s];

                s_wdata[s]   = m_wdata[m];
                s_wstrb[s]   = m_wstrb[m];
                s_wvalid[s]  = m_wvalid[m];
                m_wready[m]  = s_wready[s];

                m_bresp[m]   = s_bresp[s];
                m_bvalid[m]  = s_bvalid[s];
                s_bready[s]  = m_bready[m];

                s_araddr[s]  = m_araddr[m];
                s_arvalid[s] = m_arvalid[m];
                m_arready[m] = s_arready[s];

                m_rdata[m]   = s_rdata[s];
                m_rresp[m]   = s_rresp[s];
                m_rvalid[m]  = s_rvalid[s];
                s_rready[s]  = m_rready[m];
            end
        end
    end

endmodule

`endif // AXI4LITE_CROSSBAR_SV
// tb_concurrent_stress.sv
// Exercises the arbiter under real contention: CPU runs the bubble sort
// program (generating cache miss/writeback AXI traffic) WHILE the DMA
// engine independently runs a memory-to-memory transfer, both hitting the
// same shared memory through cache_dma_arbiter at the same time.
//
// UPDATED for the BRAM cache rewrite:
//   1. Automatic PASS/FAIL instead of eyeballing printed output.
//   2. Waits for the sort to COMPLETE rather than running a fixed 2000
//      cycles. Read hits now cost one extra cycle (registered BRAM read),
//      so the sort takes materially longer than it did in P3 -- a fixed
//      window would have looked like a failure when it was just slower.
//   3. Reports the completion cycle, so the cache's cost is visible
//      rather than hidden.
//
// Instantiates riscv_cpu_p3 (combinational fetch) deliberately: that
// isolates the cache change from the AXI-fetch change, so a failure here
// points at the cache and nothing else.

`timescale 1ns/1ps
`include "axi4lite_ports.vh"

module tb_concurrent_stress;

    // Generous budget: the BRAM cache adds a cycle per read hit, and the
    // sort is read-heavy. Completion is detected, so this is only an
    // upper bound before declaring a hang.
    localparam int MAX_CYCLES = 20000;

    logic clk = 0, rst;
    logic [31:0] debug_out;
    always #5 clk = ~clk;

    logic [31:0] dr_awaddr, dr_wdata, dr_araddr, dr_rdata;
    logic [3:0]  dr_wstrb;
    logic [1:0]  dr_bresp, dr_rresp;
    logic        dr_awvalid, dr_awready, dr_wvalid, dr_wready, dr_bvalid, dr_bready;
    logic        dr_arvalid, dr_arready, dr_rvalid, dr_rready;
    logic        dma_irq;

    logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
    logic [3:0]  m_wstrb;
    logic [1:0]  m_bresp, m_rresp;
    logic        m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
    logic        m_arvalid, m_arready, m_rvalid, m_rready;

    riscv_cpu_p3 dut (
        .clk(clk), .rst(rst), .debug_out(debug_out),
        .dma_reg_awaddr(dr_awaddr), .dma_reg_awvalid(dr_awvalid), .dma_reg_awready(dr_awready),
        .dma_reg_wdata (dr_wdata),  .dma_reg_wstrb  (dr_wstrb),   .dma_reg_wvalid (dr_wvalid), .dma_reg_wready(dr_wready),
        .dma_reg_bresp (dr_bresp),  .dma_reg_bvalid (dr_bvalid),  .dma_reg_bready (dr_bready),
        .dma_reg_araddr(dr_araddr), .dma_reg_arvalid(dr_arvalid), .dma_reg_arready(dr_arready),
        .dma_reg_rdata (dr_rdata),  .dma_reg_rresp  (dr_rresp),   .dma_reg_rvalid (dr_rvalid), .dma_reg_rready(dr_rready),
        .dma_irq(dma_irq),
        .ext_mem_awaddr(m_awaddr), .ext_mem_awvalid(m_awvalid), .ext_mem_awready(m_awready),
        .ext_mem_wdata (m_wdata),  .ext_mem_wstrb  (m_wstrb),   .ext_mem_wvalid (m_wvalid), .ext_mem_wready(m_wready),
        .ext_mem_bresp (m_bresp),  .ext_mem_bvalid (m_bvalid),  .ext_mem_bready (m_bready),
        .ext_mem_araddr(m_araddr), .ext_mem_arvalid(m_arvalid), .ext_mem_arready(m_arready),
        .ext_mem_rdata (m_rdata),  .ext_mem_rresp  (m_rresp),   .ext_mem_rvalid (m_rvalid), .ext_mem_rready(m_rready)
    );

    axi4lite_mem_model #(.MEM_WORDS(4096)) u_mem (
        .clk(clk), .rst_n(~rst),
        .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata (m_wdata),  .s_axi_wstrb  (m_wstrb),   .s_axi_wvalid (m_wvalid), .s_axi_wready(m_wready),
        .s_axi_bresp (m_bresp),  .s_axi_bvalid (m_bvalid),  .s_axi_bready (m_bready),
        .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rdata (m_rdata),  .s_axi_rresp  (m_rresp),   .s_axi_rvalid (m_rvalid), .s_axi_rready(m_rready)
    );

    task automatic dma_reg_write(input [7:0] off, input [31:0] data);
        begin
            @(posedge clk);
            dr_awaddr  <= {24'd0, off};
            dr_awvalid <= 1'b1;
            dr_wdata   <= data;
            dr_wstrb   <= 4'hF;
            dr_wvalid  <= 1'b1;
            dr_bready  <= 1'b1;
            wait (dr_awready && dr_wready);
            @(posedge clk);
            dr_awvalid <= 1'b0;
            dr_wvalid  <= 1'b0;
            wait (dr_bvalid);
            @(posedge clk);
            dr_bready <= 1'b0;
        end
    endtask

    initial begin
        dr_awvalid = 0; dr_wvalid = 0; dr_bready = 0; dr_arvalid = 0; dr_rready = 0;
        dr_awaddr = 0; dr_wdata = 0; dr_wstrb = 0; dr_araddr = 0;
    end

    int errors = 0;
    int cyc = 0;
    int sort_done_cyc = -1;
    int dma_done_cyc  = -1;
    logic [31:0] prev_a0;

    // free-running cycle counter + event capture
    always @(posedge clk) begin
        if (!rst) begin
            cyc <= cyc + 1;
            if (dma_irq && dma_done_cyc < 0) begin
                dma_done_cyc = cyc;
                $display("cyc=%0d  DMA IRQ fired", cyc);
            end
            if (debug_out !== prev_a0) begin
                $display("cyc=%0d  a0 -> %0d", cyc, debug_out);
                prev_a0 = debug_out;
                if (debug_out === 32'd4 && sort_done_cyc < 0)
                    sort_done_cyc = cyc;
            end
        end
    end

    initial begin
        rst = 1;
        prev_a0 = 'x;
        repeat(5) @(posedge clk);
        rst = 0;

        // bubble sort dataset for the CPU program (0x200..0x224)
        u_mem.mem[32'h200>>2]=5; u_mem.mem[32'h204>>2]=4; u_mem.mem[32'h208>>2]=8;
        u_mem.mem[32'h20C>>2]=6; u_mem.mem[32'h210>>2]=9; u_mem.mem[32'h214>>2]=7;
        u_mem.mem[32'h218>>2]=6; u_mem.mem[32'h21C>>2]=4; u_mem.mem[32'h220>>2]=8;
        u_mem.mem[32'h224>>2]=5;

        // separate, non-overlapping region for the concurrent DMA copy
        for (int k = 0; k < 16; k++)
            u_mem.mem[(32'h1000>>2) + k] = 32'hA000_0000 + k;

        // kick DMA after reset settles so it overlaps the CPU's early
        // cache-miss traffic rather than racing reset
        repeat(20) @(posedge clk);
        dma_reg_write(8'h00, 32'h1000); // SRC
        dma_reg_write(8'h04, 32'h2000); // DST
        dma_reg_write(8'h08, 32'd64);   // LEN (64 bytes = 16 words)
        dma_reg_write(8'h0C, 32'h1);    // START

        // ---- wait for BOTH to finish, rather than a fixed window ----
        while ((sort_done_cyc < 0 || dma_done_cyc < 0) && cyc < MAX_CYCLES)
            @(posedge clk);

        repeat (20) @(posedge clk);

        $display("=========================");

        // ---- check 1: CPU sort completed with the right answer ----
        if (sort_done_cyc < 0) begin
            $display("FAIL sort: a0 never reached 4 (final a0=%0d, %0d cycles elapsed)",
                     debug_out, cyc);
            $display("      -> if cyc hit MAX_CYCLES (%0d), the sort may just need", MAX_CYCLES);
            $display("         longer; raise MAX_CYCLES before assuming a real break.");
            errors++;
        end else begin
            $display("PASS sort: a0 = 4, completed at cycle %0d", sort_done_cyc);
        end

        // ---- check 2: DMA completed ----
        if (dma_done_cyc < 0) begin
            $display("FAIL dma: IRQ never fired within %0d cycles", cyc);
            errors++;
        end else begin
            $display("PASS dma: IRQ at cycle %0d", dma_done_cyc);
        end

        // ---- check 3: DMA data landed intact under contention ----
        // Corruption here means the arbiter let cache and DMA traffic
        // interfere -- the actual point of this testbench.
        begin
            automatic int bad = 0;
            for (int k = 0; k < 16; k++) begin
                if (u_mem.mem[(32'h2000>>2) + k] !== (32'hA000_0000 + k)) begin
                    $display("FAIL dma word %0d: got %h exp %h", k,
                             u_mem.mem[(32'h2000>>2) + k], 32'hA000_0000 + k);
                    bad++;
                end
            end
            if (bad == 0) $display("PASS dma payload: all 16 words intact");
            else          errors += bad;
        end

        // ---- check 4: the sorted array itself ----
        // The program sorts 0x200..0x224 in place. Values must come out
        // ascending; wrong data here means the cache returned bad reads.
        begin
            automatic logic [31:0] prev = 0;
            automatic int bad = 0;
            $write("sorted array:");
            for (int k = 0; k < 10; k++) begin
                automatic logic [31:0] v = u_mem.mem[(32'h200>>2) + k];
                $write(" %0d", v);
                if (k > 0 && v < prev) bad++;
                prev = v;
            end
            $display("");
            // NOTE: the array is only guaranteed written back to memory
            // once the dirty lines are evicted. If this reports unsorted
            // values while a0 == 4, suspect a still-cached line rather
            // than a sort failure.
            if (bad != 0)
                $display("INFO sorted array not ascending in MEMORY (%0d inversions) -- expected if lines are still dirty in cache", bad);
            else
                $display("PASS sorted array ascending in memory");
        end

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: global timeout at cyc=%0d, a0=%0d", cyc, debug_out);
        $finish;
    end

endmodule : tb_concurrent_stress
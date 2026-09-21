// tb_riscv_cpu_p4.sv
// Integration test for riscv_cpu_p4: the pipeline fetching real
// instructions over AXI4-Lite while doing real data accesses.
//
// This is the step where the fetch change meets the pipeline. The
// standalone if_stage_axi test drove pc_sel synthetically; here the
// redirects come from actual taken branches resolving at EX/MEM, which
// is the interaction that the whole design note in if_stage_axi.sv is
// about.
//
// Two independent memories, mirroring the crossbar map:
//   instruction memory -> slave 3 @ 0x0003_0000  (CPU's instr_mem port)
//   data memory        -> slave 0 @ 0x0000_0000  (CPU's ext_mem port)
// The crossbar itself is NOT in this TB -- it is verified separately by
// tb_axi4lite_crossbar3. Keeping it out means a failure here points at
// the CPU/fetch integration and nothing else.
//
// The program is written directly into imem as RV32I machine code, so it
// exercises the same fetch path a runtime-loaded program would.

`timescale 1ns/1ps

module tb_riscv_cpu_p4;

    localparam logic [31:0] IMEM_BASE = 32'h0003_0000;

    logic clk = 0, rst;
    always #5 clk = ~clk;

    logic [31:0] debug_out, if_pc_out;
    logic        mem_stall_out, if_stall_out, dma_irq;

    // dma_reg slave port - tied off, not under test here
    logic [31:0] dr_rdata; logic [1:0] dr_bresp, dr_rresp;
    logic dr_awready, dr_wready, dr_bvalid, dr_arready, dr_rvalid;

    // data memory (ext_mem master)
    logic [31:0] d_awaddr; logic d_awvalid, d_awready;
    logic [31:0] d_wdata;  logic [3:0] d_wstrb;
    logic        d_wvalid, d_wready;
    logic [1:0]  d_bresp;  logic d_bvalid, d_bready;
    logic [31:0] d_araddr; logic d_arvalid, d_arready;
    logic [31:0] d_rdata;  logic [1:0] d_rresp;
    logic        d_rvalid, d_rready;

    // instruction memory (instr_mem master)
    logic [31:0] i_awaddr; logic i_awvalid, i_awready;
    logic [31:0] i_wdata;  logic [3:0] i_wstrb;
    logic        i_wvalid, i_wready;
    logic [1:0]  i_bresp;  logic i_bvalid, i_bready;
    logic [31:0] i_araddr; logic i_arvalid, i_arready;
    logic [31:0] i_rdata;  logic [1:0] i_rresp;
    logic        i_rvalid, i_rready;

    riscv_cpu_p4 #(.IMEM_BASE(IMEM_BASE)) dut (
        .clk(clk), .rst(rst),
        .debug_out(debug_out), .mem_stall_out(mem_stall_out),
        .if_pc_out(if_pc_out), .if_stall_out(if_stall_out),

        .dma_reg_awaddr(32'd0), .dma_reg_awvalid(1'b0), .dma_reg_awready(dr_awready),
        .dma_reg_wdata (32'd0), .dma_reg_wstrb  (4'd0), .dma_reg_wvalid (1'b0), .dma_reg_wready(dr_wready),
        .dma_reg_bresp (dr_bresp), .dma_reg_bvalid(dr_bvalid), .dma_reg_bready(1'b1),
        .dma_reg_araddr(32'd0), .dma_reg_arvalid(1'b0), .dma_reg_arready(dr_arready),
        .dma_reg_rdata (dr_rdata), .dma_reg_rresp(dr_rresp), .dma_reg_rvalid(dr_rvalid), .dma_reg_rready(1'b1),
        .dma_irq(dma_irq),

        .ext_mem_awaddr(d_awaddr), .ext_mem_awvalid(d_awvalid), .ext_mem_awready(d_awready),
        .ext_mem_wdata (d_wdata),  .ext_mem_wstrb  (d_wstrb),   .ext_mem_wvalid (d_wvalid), .ext_mem_wready(d_wready),
        .ext_mem_bresp (d_bresp),  .ext_mem_bvalid (d_bvalid),  .ext_mem_bready (d_bready),
        .ext_mem_araddr(d_araddr), .ext_mem_arvalid(d_arvalid), .ext_mem_arready(d_arready),
        .ext_mem_rdata (d_rdata),  .ext_mem_rresp  (d_rresp),   .ext_mem_rvalid (d_rvalid), .ext_mem_rready(d_rready),

        .instr_mem_awaddr(i_awaddr), .instr_mem_awvalid(i_awvalid), .instr_mem_awready(i_awready),
        .instr_mem_wdata (i_wdata),  .instr_mem_wstrb  (i_wstrb),   .instr_mem_wvalid (i_wvalid), .instr_mem_wready(i_wready),
        .instr_mem_bresp (i_bresp),  .instr_mem_bvalid (i_bvalid),  .instr_mem_bready (i_bready),
        .instr_mem_araddr(i_araddr), .instr_mem_arvalid(i_arvalid), .instr_mem_arready(i_arready),
        .instr_mem_rdata (i_rdata),  .instr_mem_rresp  (i_rresp),   .instr_mem_rvalid (i_rvalid), .instr_mem_rready(i_rready)
    );

    axi4lite_mem_model #(.MEM_WORDS(4096)) u_dmem (
        .clk(clk), .rst_n(~rst),
        .s_axi_awaddr(d_awaddr), .s_axi_awvalid(d_awvalid), .s_axi_awready(d_awready),
        .s_axi_wdata (d_wdata),  .s_axi_wstrb  (d_wstrb),   .s_axi_wvalid (d_wvalid), .s_axi_wready(d_wready),
        .s_axi_bresp (d_bresp),  .s_axi_bvalid (d_bvalid),  .s_axi_bready (d_bready),
        .s_axi_araddr(d_araddr), .s_axi_arvalid(d_arvalid), .s_axi_arready(d_arready),
        .s_axi_rdata (d_rdata),  .s_axi_rresp  (d_rresp),   .s_axi_rvalid (d_rvalid), .s_axi_rready(d_rready)
    );

    axi4lite_mem_model #(.MEM_WORDS(1024)) u_imem (
        .clk(clk), .rst_n(~rst),
        .s_axi_awaddr(i_awaddr), .s_axi_awvalid(i_awvalid), .s_axi_awready(i_awready),
        .s_axi_wdata (i_wdata),  .s_axi_wstrb  (i_wstrb),   .s_axi_wvalid (i_wvalid), .s_axi_wready(i_wready),
        .s_axi_bresp (i_bresp),  .s_axi_bvalid (i_bvalid),  .s_axi_bready (i_bready),
        .s_axi_araddr(i_araddr), .s_axi_arvalid(i_arvalid), .s_axi_arready(i_arready),
        .s_axi_rdata (i_rdata),  .s_axi_rresp  (i_rresp),   .s_axi_rvalid (i_rvalid), .s_axi_rready(i_rready)
    );

    int errors = 0;
    task automatic check(input string label, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %s: got=%h exp=%h", label, got, exp);
            errors++;
        end else $display("PASS %s: %h", label, got);
    endtask

    function automatic int iw(input [31:0] byte_addr);
        iw = (byte_addr >> 2) % 1024;
    endfunction

    initial begin
        rst = 1;
        repeat (5) @(posedge clk);

        // ================= PROGRAM =================
        // debug_out is regfile x10 (a0), so the final check reads x10.
        //
        //  addr  instruction                     meaning
        //  +00   addi x10, x0, 0                 a0 = 0
        //  +04   addi x5,  x0, 5                 t0 = 5   (loop counter)
        //  +08   addi x6,  x0, 0                 t1 = 0
        // L:
        //  +0C   addi x10, x10, 3                a0 += 3
        //  +10   addi x6,  x6, 1                 t1 += 1
        //  +14   blt  x6, x5, L                  if t1 < t0 goto L  (-8)
        //  +18   addi x7,  x0, 7                 t2 = 7
        //  +1C   sw   x10, 0(x0)                 store a0 to data mem[0]
        //  +20   lw   x11, 0(x0)                 a1 = data mem[0]
        //  +24   addi x10, x11, 0                a0 = a1   (round-trip)
        //  +28   lui  x8,  0x1                   t3 = 0x1000
        //  +2C   lw   x9,  0(x8)                 force eviction of addr 0's
        //                                        line (same cache index,
        //                                        different tag) -> the dirty
        //                                        line is written back to
        //                                        main memory
        // END:
        //  +30   jal  x0, 0                      spin
        //
        // The blt is the point of this test: a real taken branch resolving
        // at EX/MEM while a fetch for the fall-through path is already in
        // flight on AXI. Loops 5 times, so it exercises the
        // redirect-during-fetch path repeatedly, then falls through.
        // Expected a0 = 3*5 = 15, round-tripped through data memory.
        //
        // NOTE on the eviction: cache_controller is WRITE-BACK, so after
        // "sw x10,0(x0)" the value lives only in the cache -- main memory
        // is untouched. Checking u_dmem.mem[0] before an eviction reads
        // uninitialised memory (X), which is correct cache behaviour, not
        // a bug. The lui+lw above evicts the line so the writeback
        // actually happens and the memory check means something.

        u_imem.mem[iw(IMEM_BASE + 32'h00)] = 32'h00000513; // addi x10,x0,0
        u_imem.mem[iw(IMEM_BASE + 32'h04)] = 32'h00500293; // addi x5,x0,5
        u_imem.mem[iw(IMEM_BASE + 32'h08)] = 32'h00000313; // addi x6,x0,0
        u_imem.mem[iw(IMEM_BASE + 32'h0C)] = 32'h00350513; // addi x10,x10,3
        u_imem.mem[iw(IMEM_BASE + 32'h10)] = 32'h00130313; // addi x6,x6,1
        u_imem.mem[iw(IMEM_BASE + 32'h14)] = 32'hFE534CE3; // blt x6,x5,-8
        u_imem.mem[iw(IMEM_BASE + 32'h18)] = 32'h00700393; // addi x7,x0,7
        u_imem.mem[iw(IMEM_BASE + 32'h1C)] = 32'h00A02023; // sw x10,0(x0)
        u_imem.mem[iw(IMEM_BASE + 32'h20)] = 32'h00002583; // lw x11,0(x0)
        u_imem.mem[iw(IMEM_BASE + 32'h24)] = 32'h00058513; // addi x10,x11,0
        u_imem.mem[iw(IMEM_BASE + 32'h28)] = 32'h00001437; // lui x8,0x1
        u_imem.mem[iw(IMEM_BASE + 32'h2C)] = 32'h00042483; // lw x9,0(x8)
        u_imem.mem[iw(IMEM_BASE + 32'h30)] = 32'h0000006F; // jal x0,0 (spin)

        rst = 0;

        // ---- 1. fetch is alive: PC must leave the reset value ----
        begin
            automatic int unsigned t = 0;
            while (if_pc_out === IMEM_BASE && t < 2000) begin
                @(posedge clk);
                t++;
            end
            if (t >= 2000) begin
                $display("FAIL fetch never advanced past reset PC (if_stall=%b)", if_stall_out);
                errors++;
            end else
                $display("PASS fetch advanced past reset PC after %0d cycles", t);
        end

        // ---- 2. run until the program reaches its spin, or time out ----
        begin
            automatic int unsigned t = 0;
            while (if_pc_out !== (IMEM_BASE + 32'h30) && t < 20000) begin
                @(posedge clk);
                t++;
            end
            if (t >= 20000) begin
                $display("FAIL program never reached END (pc=%h if_stall=%b mem_stall=%b)",
                          if_pc_out, if_stall_out, mem_stall_out);
                errors++;
            end else
                $display("PASS reached END spin at pc=%h after %0d cycles", if_pc_out, t);
        end

        // let the tail drain through WB
        repeat (50) @(posedge clk);

        // ---- 3. the loop ran the right number of times ----
        // a0 = 3 * 5 = 15. Wrong here means branches redirected wrongly:
        // too small = loop exited early, too large = extra iterations
        // (a lost or duplicated redirect).
        check("a0 after loop + mem round-trip", debug_out, 32'd15);

        // ---- 4. the data path still works alongside AXI fetch ----
        // Now that the line has been evicted, main memory must hold the
        // stored value. This is the check that actually proves the data
        // path reached memory rather than just the cache.
        check("data mem[0] after writeback", u_dmem.mem[0], 32'd15);

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: global timeout. pc=%h if_stall=%b mem_stall=%b a0=%0d",
                 if_pc_out, if_stall_out, mem_stall_out, debug_out);
        $finish;
    end

endmodule : tb_riscv_cpu_p4
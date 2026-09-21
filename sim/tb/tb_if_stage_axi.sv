// tb_if_stage_axi.sv
// Unit test for if_stage_axi.sv, standalone against a memory model --
// no CPU, no crossbar. Run this BEFORE integrating into riscv_cpu_p3.
//
// The happy path (fetch instructions in order) is the easy part and is
// unlikely to be where bugs live. These tests target the three cases
// that actually make AXI fetch hard:
//
//   T1 sequential fetch  -- baseline; PC advances by 4, right data
//   T2 stall hold        -- pc_write low must hold the instruction, not
//                           skip or refetch it
//   T3 branch redirect   -- redirect while idle: next fetch is the target
//   T4 mid-flight redirect -- THE important one. Redirect arrives while a
//                           fetch is outstanding. The in-flight read must
//                           still complete on AXI (no abort exists), its
//                           data must be DISCARDED, and the redirect must
//                           NOT be lost even though it is a one-cycle
//                           pulse arriving during a stall.
//   T5 no lost redirect  -- redirect pulse during IF_WAIT, verified by
//                           checking the CPU-visible instruction stream
//                           rather than internal state.

`timescale 1ns/1ps

module tb_if_stage_axi;

    localparam logic [31:0] IMEM_BASE = 32'h0003_0000;

    logic clk = 0, rst;
    always #5 clk = ~clk;

    logic        pc_write, pc_sel;
    logic [31:0] branch_target;
    logic [31:0] instr, pc, pc_plus4;
    logic        if_stall;

    logic [31:0] i_awaddr; logic i_awvalid, i_awready;
    logic [31:0] i_wdata;  logic [3:0] i_wstrb;
    logic        i_wvalid, i_wready;
    logic [1:0]  i_bresp;  logic i_bvalid, i_bready;
    logic [31:0] i_araddr; logic i_arvalid, i_arready;
    logic [31:0] i_rdata;  logic [1:0] i_rresp;
    logic        i_rvalid, i_rready;

    if_stage_axi #(.IMEM_BASE(IMEM_BASE)) dut (
        .clk(clk), .rst(rst),
        .pc_write(pc_write), .pc_sel(pc_sel), .branch_target(branch_target),
        .instr(instr), .pc(pc), .pc_plus4(pc_plus4),
        .if_stall(if_stall),
        .i_axi_awaddr(i_awaddr), .i_axi_awvalid(i_awvalid), .i_axi_awready(i_awready),
        .i_axi_wdata (i_wdata),  .i_axi_wstrb  (i_wstrb),   .i_axi_wvalid (i_wvalid), .i_axi_wready(i_wready),
        .i_axi_bresp (i_bresp),  .i_axi_bvalid (i_bvalid),  .i_axi_bready (i_bready),
        .i_axi_araddr(i_araddr), .i_axi_arvalid(i_arvalid), .i_axi_arready(i_arready),
        .i_axi_rdata (i_rdata),  .i_axi_rresp  (i_rresp),   .i_axi_rvalid (i_rvalid), .i_axi_rready(i_rready)
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

    // Wait until the fetch unit presents a NEW instruction.
    //
    // Waiting only for "if_stall low" is not enough: if the DUT is still
    // sitting in IF_VALID holding the PREVIOUS instruction when this is
    // called, the loop exits instantly and samples stale data. That is
    // exactly what made T4 report the in-flight wrong-path PC (0x30044)
    // while the DUT was in fact discarding it correctly.
    //
    // So: first wait for a fetch to be genuinely underway (if_stall high),
    // then wait for it to complete.
    task automatic await_instr(input string label, output [31:0] got_instr,
                               output [31:0] got_pc);
        int unsigned t;
        begin
            t = 0;
            // phase 1: fetch in progress
            while (!if_stall && t < 200) begin
                @(posedge clk);
                t++;
            end
            // phase 2: fetch complete
            while (if_stall && t < 200) begin
                @(posedge clk);
                t++;
            end
            if (t >= 200) begin
                $display("FAIL %s: timeout waiting for fetch (if_stall stuck)", label);
                errors++;
            end
            got_instr = instr;
            got_pc    = pc;
        end
    endtask

    logic [31:0] gi, gp;
    // mem_model indexes by word: address 0x0003_0000 -> (0x30000>>2) % 1024
    function automatic int imem_idx(input [31:0] byte_addr);
        imem_idx = (byte_addr >> 2) % 1024;
    endfunction

    initial begin
        pc_write = 1'b1; pc_sel = 1'b0; branch_target = 32'd0;
        rst = 1;
        repeat (5) @(posedge clk);

        // Seed instruction memory with recognisable per-address values so
        // a wrong-path fetch is obvious in the log rather than subtle.
        u_imem.mem[imem_idx(IMEM_BASE + 32'h00)] = 32'h1111_0000;
        u_imem.mem[imem_idx(IMEM_BASE + 32'h04)] = 32'h1111_0004;
        u_imem.mem[imem_idx(IMEM_BASE + 32'h08)] = 32'h1111_0008;
        u_imem.mem[imem_idx(IMEM_BASE + 32'h0C)] = 32'h1111_000C;
        u_imem.mem[imem_idx(IMEM_BASE + 32'h40)] = 32'hBBBB_0040;  // branch target
        u_imem.mem[imem_idx(IMEM_BASE + 32'h80)] = 32'hCCCC_0080;  // 2nd target

        rst = 0;
        @(posedge clk);

        // ---- T1: sequential fetch ----
        await_instr("T1 fetch0", gi, gp);
        check("T1 instr @base+0", gi, 32'h1111_0000);
        check("T1 pc    @base+0", gp, IMEM_BASE + 32'h00);
        @(posedge clk);

        await_instr("T1 fetch1", gi, gp);
        check("T1 instr @base+4", gi, 32'h1111_0004);
        check("T1 pc    @base+4", gp, IMEM_BASE + 32'h04);
        @(posedge clk);

        // ---- T2: pc_write low must HOLD, not advance or refetch ----
        pc_write = 1'b0;
        await_instr("T2 hold", gi, gp);
        check("T2 instr held", gi, 32'h1111_0008);
        repeat (5) @(posedge clk);
        check("T2 instr still held after 5 cyc", instr, 32'h1111_0008);
        check("T2 pc unchanged",                 pc,    IMEM_BASE + 32'h08);
        pc_write = 1'b1;
        @(posedge clk);

        await_instr("T2 resume", gi, gp);
        check("T2 advanced after release", gi, 32'h1111_000C);
        @(posedge clk);

        // ---- T3: redirect while instruction is being consumed ----
        pc_sel        = 1'b1;
        branch_target = IMEM_BASE + 32'h40;
        @(posedge clk);
        pc_sel        = 1'b0;

        await_instr("T3 redirect", gi, gp);
        check("T3 instr @target", gi, 32'hBBBB_0040);
        check("T3 pc    @target", gp, IMEM_BASE + 32'h40);
        @(posedge clk);

        // ---- T4 / T5: redirect pulse arriving MID-FLIGHT ----
        // Wait for a fetch to actually be outstanding (if_stall high), then
        // pulse pc_sel for exactly one cycle -- the same shape the real
        // ex_mem_branch_taken pulse has. If the redirect is gated rather
        // than latched, it is silently lost here and the fetch unit
        // continues down the wrong path.
        @(posedge clk);
        while (!if_stall) @(posedge clk);   // now mid-fetch

        pc_sel        = 1'b1;
        branch_target = IMEM_BASE + 32'h80;
        @(posedge clk);
        pc_sel        = 1'b0;               // one-cycle pulse, now gone

        await_instr("T4 midflight redirect", gi, gp);
        check("T4 instr @2nd target", gi, 32'hCCCC_0080);
        check("T4 pc    @2nd target", gp, IMEM_BASE + 32'h80);

        // ---- T5: AXI channel still sane after the discarded fetch ----
        // If the wrong-path read desynchronised the R channel, the next
        // sequential fetch returns stale or wrong data.
        @(posedge clk);
        u_imem.mem[imem_idx(IMEM_BASE + 32'h84)] = 32'hCCCC_0084;
        await_instr("T5 post-discard", gi, gp);
        check("T5 next instr correct", gi, 32'hCCCC_0084);
        check("T5 next pc correct",    gp, IMEM_BASE + 32'h84);

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

    initial begin
        #200000;
        $display("FAIL: global timeout. state=%0d if_stall=%b pc=%h",
                 dut.state_q, if_stall, pc);
        $finish;
    end

endmodule : tb_if_stage_axi
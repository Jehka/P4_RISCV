// tb_p4_system.sv  (P4 + AXI instruction fetch)
//
// End-to-end test of p4_top: the CPU fetching instructions over the
// crossbar from slave 3 while doing data accesses through slave 0, with
// the fault-injection master on master 1 able to reach BOTH.
//
// This is the test that demonstrates what the fetch change bought:
//   T2/T3 inject faults into DATA memory        (already possible in P4)
//   T5    injects a fault into INSTRUCTION memory -- impossible before,
//         because imem was a ROM inside if_stage and unreachable from
//         the fabric.
//
// Topology, matching p4_top:
//   m0 CPU data | m1 FI master | m2 CPU fetch
//   s0 data mem | s1 dma_reg (internal) | s2 periph (tied off) | s3 imem

`timescale 1ns/1ps

module tb_p4_system;

    localparam logic [31:0] IMEM_BASE = 32'h0003_0000;

    logic clk = 0, rst;
    always #5 clk = ~clk;

    logic [31:0] debug_out, if_pc_out;
    logic        mem_stall_out, if_stall_out, dma_irq, fi_irq;

    // slave 0: data memory
    logic [31:0] d_awaddr; logic d_awvalid, d_awready;
    logic [31:0] d_wdata;  logic [3:0] d_wstrb;
    logic        d_wvalid, d_wready;
    logic [1:0]  d_bresp;  logic d_bvalid, d_bready;
    logic [31:0] d_araddr; logic d_arvalid, d_arready;
    logic [31:0] d_rdata;  logic [1:0] d_rresp;
    logic        d_rvalid, d_rready;

    // slave 3: instruction memory
    logic [31:0] i_awaddr; logic i_awvalid, i_awready;
    logic [31:0] i_wdata;  logic [3:0] i_wstrb;
    logic        i_wvalid, i_wready;
    logic [1:0]  i_bresp;  logic i_bvalid, i_bready;
    logic [31:0] i_araddr; logic i_arvalid, i_arready;
    logic [31:0] i_rdata;  logic [1:0] i_rresp;
    logic        i_rvalid, i_rready;

    // slave 2: periph, tied off SAFE (ready high / valid low). Leaving it
    // dangling would hold the crossbar grant forever on a stray access.
    logic [31:0] p_awaddr; logic p_awvalid;
    logic [31:0] p_wdata;  logic [3:0] p_wstrb;
    logic        p_wvalid, p_bready;
    logic [31:0] p_araddr; logic p_arvalid, p_rready;

    // fi_cfg programming port
    logic [31:0] fi_awaddr; logic fi_awvalid, fi_awready;
    logic [31:0] fi_wdata;  logic [3:0] fi_wstrb;
    logic        fi_wvalid, fi_wready;
    logic [1:0]  fi_bresp;  logic fi_bvalid, fi_bready;
    logic [31:0] fi_araddr; logic fi_arvalid, fi_arready;
    logic [31:0] fi_rdata;  logic [1:0] fi_rresp;
    logic        fi_rvalid, fi_rready;

    p4_top dut (
        .clk(clk), .rst(rst),
        .debug_out(debug_out), .mem_stall_out(mem_stall_out),
        .if_stall_out(if_stall_out), .if_pc_out(if_pc_out),
        .dma_irq(dma_irq), .fi_irq(fi_irq),

        .ext_mem_awaddr(d_awaddr), .ext_mem_awvalid(d_awvalid), .ext_mem_awready(d_awready),
        .ext_mem_wdata (d_wdata),  .ext_mem_wstrb  (d_wstrb),   .ext_mem_wvalid (d_wvalid), .ext_mem_wready(d_wready),
        .ext_mem_bresp (d_bresp),  .ext_mem_bvalid (d_bvalid),  .ext_mem_bready (d_bready),
        .ext_mem_araddr(d_araddr), .ext_mem_arvalid(d_arvalid), .ext_mem_arready(d_arready),
        .ext_mem_rdata (d_rdata),  .ext_mem_rresp  (d_rresp),   .ext_mem_rvalid (d_rvalid), .ext_mem_rready(d_rready),

        .periph_awaddr(p_awaddr), .periph_awvalid(p_awvalid), .periph_awready(1'b1),
        .periph_wdata (p_wdata),  .periph_wstrb  (p_wstrb),   .periph_wvalid (p_wvalid), .periph_wready(1'b1),
        .periph_bresp (2'b00),    .periph_bvalid (1'b0),      .periph_bready (p_bready),
        .periph_araddr(p_araddr), .periph_arvalid(p_arvalid), .periph_arready(1'b1),
        .periph_rdata (32'd0),    .periph_rresp  (2'b00),     .periph_rvalid (1'b0), .periph_rready(p_rready),

        .imem_awaddr(i_awaddr), .imem_awvalid(i_awvalid), .imem_awready(i_awready),
        .imem_wdata (i_wdata),  .imem_wstrb  (i_wstrb),   .imem_wvalid (i_wvalid), .imem_wready(i_wready),
        .imem_bresp (i_bresp),  .imem_bvalid (i_bvalid),  .imem_bready (i_bready),
        .imem_araddr(i_araddr), .imem_arvalid(i_arvalid), .imem_arready(i_arready),
        .imem_rdata (i_rdata),  .imem_rresp  (i_rresp),   .imem_rvalid (i_rvalid), .imem_rready(i_rready),

        .fi_cfg_awaddr(fi_awaddr), .fi_cfg_awvalid(fi_awvalid), .fi_cfg_awready(fi_awready),
        .fi_cfg_wdata (fi_wdata),  .fi_cfg_wstrb  (fi_wstrb),   .fi_cfg_wvalid (fi_wvalid), .fi_cfg_wready(fi_wready),
        .fi_cfg_bresp (fi_bresp),  .fi_cfg_bvalid (fi_bvalid),  .fi_cfg_bready (fi_bready),
        .fi_cfg_araddr(fi_araddr), .fi_cfg_arvalid(fi_arvalid), .fi_cfg_arready(fi_arready),
        .fi_cfg_rdata (fi_rdata),  .fi_cfg_rresp  (fi_rresp),   .fi_cfg_rvalid (fi_rvalid), .fi_cfg_rready(fi_rready)
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

    task automatic fi_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            fi_awaddr <= addr; fi_awvalid <= 1'b1;
            fi_wdata  <= data; fi_wstrb   <= 4'hF; fi_wvalid <= 1'b1;
            fi_bready <= 1'b1;
            wait (fi_awready && fi_wready);
            @(posedge clk);
            fi_awvalid <= 1'b0; fi_wvalid <= 1'b0;
            wait (fi_bvalid);
            @(posedge clk);
            fi_bready <= 1'b0;
        end
    endtask

    task automatic fi_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            fi_araddr <= addr; fi_arvalid <= 1'b1; fi_rready <= 1'b1;
            wait (fi_arready);
            @(posedge clk);
            fi_arvalid <= 1'b0;
            wait (fi_rvalid);
            data = fi_rdata;
            @(posedge clk);
            fi_rready <= 1'b0;
        end
    endtask

    task automatic fi_campaign(input string label, input [31:0] target,
                               input [31:0] data, input [31:0] mask,
                               input bit mode1);
        int unsigned t; logic [31:0] st;
        begin
            fi_write(32'h00, target);
            fi_write(32'h04, data);
            fi_write(32'h08, mask);
            fi_write(32'h0C, mode1 ? 32'h3 : 32'h1);   // START (| MODE)
            t = 0;
            forever begin
                fi_read(32'h10, st);
                if (st[1]) break;                       // DONE
                t++;
                if (t > 500) begin
                    $display("FAIL %s: FI timeout (status=%h)", label, st);
                    errors++; break;
                end
            end
            if (st[2]) begin
                $display("FAIL %s: FI reported ERROR (status=%h)", label, st);
                errors++;
            end
            fi_write(32'h10, 32'h2);                    // W1C DONE
        end
    endtask

    function automatic int iw(input [31:0] byte_addr);
        iw = (byte_addr >> 2) % 1024;
    endfunction

    initial begin
        fi_awvalid = 0; fi_wvalid = 0; fi_bready = 0;
        fi_arvalid = 0; fi_rready = 0;
        fi_awaddr = 0; fi_wdata = 0; fi_wstrb = 0; fi_araddr = 0;

        rst = 1;
        repeat (10) @(posedge clk);

        // ---- program (same as tb_riscv_cpu_p4) ----
        //  +00 addi x10,x0,0     +04 addi x5,x0,5    +08 addi x6,x0,0
        //  +0C addi x10,x10,3    +10 addi x6,x6,1    +14 blt x6,x5,-8
        //  +18 addi x7,x0,7      +1C sw x10,0(x0)    +20 lw x11,0(x0)
        //  +24 addi x10,x11,0    +28 lui x8,1        +2C lw x9,0(x8)
        //  +30 jal x0,0 (spin)
        u_imem.mem[iw(IMEM_BASE + 32'h00)] = 32'h00000513;
        u_imem.mem[iw(IMEM_BASE + 32'h04)] = 32'h00500293;
        u_imem.mem[iw(IMEM_BASE + 32'h08)] = 32'h00000313;
        u_imem.mem[iw(IMEM_BASE + 32'h0C)] = 32'h00350513;
        u_imem.mem[iw(IMEM_BASE + 32'h10)] = 32'h00130313;
        u_imem.mem[iw(IMEM_BASE + 32'h14)] = 32'hFE534CE3;
        u_imem.mem[iw(IMEM_BASE + 32'h18)] = 32'h00700393;
        u_imem.mem[iw(IMEM_BASE + 32'h1C)] = 32'h00A02023;
        u_imem.mem[iw(IMEM_BASE + 32'h20)] = 32'h00002583;
        u_imem.mem[iw(IMEM_BASE + 32'h24)] = 32'h00058513;
        u_imem.mem[iw(IMEM_BASE + 32'h28)] = 32'h00001437;
        u_imem.mem[iw(IMEM_BASE + 32'h2C)] = 32'h00042483;
        u_imem.mem[iw(IMEM_BASE + 32'h30)] = 32'h0000006F;

        rst = 0;

        // ---- T1: CPU fetches through the crossbar and runs to completion
        begin
            automatic int unsigned t = 0;
            while (if_pc_out !== (IMEM_BASE + 32'h30) && t < 20000) begin
                @(posedge clk);
                t++;
            end
            if (t >= 20000) begin
                $display("FAIL T1: never reached END (pc=%h if_stall=%b mem_stall=%b)",
                         if_pc_out, if_stall_out, mem_stall_out);
                errors++;
            end else
                $display("PASS T1: ran to END through crossbar in %0d cycles", t);
        end
        repeat (50) @(posedge clk);
        check("T1 a0 correct", debug_out, 32'd15);

        // ---- T2: FI master reaches DATA memory while the CPU runs ----
        fi_campaign("T2", 32'h0000_0800, 32'hFEED_FACE, 32'd0, 1'b0);
        check("T2 data-mem injection landed", u_dmem.mem[32'h800>>2], 32'hFEED_FACE);

        // ---- T3: MODE 1 bit-flip on data memory, through the fabric ----
        fi_campaign("T3", 32'h0000_0800, 32'd0, 32'h0000_FFFF, 1'b1);
        check("T3 data-mem bitflip", u_dmem.mem[32'h800>>2], 32'hFEED_0531);

        // ---- T4: CPU survived the data-side campaigns ----
        // The spin is "jal x0,0" at +0x30, but branches resolve at EX/MEM,
        // so the fetch unit runs ahead to +0x34 before the redirect pulls
        // it back. if_pc_out therefore oscillates between 0x30 and 0x34 --
        // sampling a single instant and demanding exactly 0x30 is a
        // coin flip, and shifted onto the wrong side when the BRAM cache
        // changed timing by a cycle. Watch the loop instead: the PC must
        // return to the jal, and must never leave the spin region.
        begin
            automatic bit saw_jal   = 0;
            automatic bit escaped   = 0;
            for (int i = 0; i < 200; i++) begin
                if (if_pc_out === (IMEM_BASE + 32'h30)) saw_jal = 1;
                if (if_pc_out !== (IMEM_BASE + 32'h30) &&
                    if_pc_out !== (IMEM_BASE + 32'h34)) escaped = 1;
                @(posedge clk);
            end
            if (!saw_jal || escaped) begin
                $display("FAIL T4 spin: saw_jal=%b escaped=%b last_pc=%h",
                         saw_jal, escaped, if_pc_out);
                errors++;
            end else
                $display("PASS T4 CPU still spinning at END (pc cycles 0x30/0x34)");
        end

        // ---- T5: INSTRUCTION fault injection ----------------------------
        // The point of the whole fetch change. imem is now crossbar slave 3,
        // so the FI master can rewrite CODE. Overwrite the spin instruction
        // at +0x30 with "addi x10,x0,42", so the spinning CPU refetches it
        // and a0 changes from 15 to 42 -- an observable instruction fault.
        fi_campaign("T5", IMEM_BASE + 32'h30, 32'h02A00513, 32'd0, 1'b0);
        check("T5 imem contents rewritten", u_imem.mem[iw(IMEM_BASE + 32'h30)],
              32'h02A00513);

        begin
            automatic int unsigned t = 0;
            while (debug_out !== 32'd42 && t < 5000) begin
                @(posedge clk);
                t++;
            end
            if (t >= 5000) begin
                $display("FAIL T5: injected instruction never executed (a0=%0d pc=%h)",
                         debug_out, if_pc_out);
                errors++;
            end else
                $display("PASS T5: injected instruction EXECUTED, a0=%0d after %0d cycles",
                         debug_out, t);
        end

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

    initial begin
        #3000000;
        $display("FAIL: global timeout. pc=%h if_stall=%b mem_stall=%b a0=%0d",
                 if_pc_out, if_stall_out, mem_stall_out, debug_out);
        $finish;
    end

endmodule : tb_p4_system
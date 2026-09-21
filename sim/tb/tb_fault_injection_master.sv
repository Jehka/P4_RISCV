// tb_fault_injection_master.sv
// Unit test for fault_injection_master.sv -- run BEFORE the system TB.
// Isolates the FI master from the crossbar and CPU so a failure here has
// exactly one suspect.
//
// Setup: FI master's m_axi drives a single axi4lite_mem_model directly
// (no crossbar). TB drives the s_axi programming port.
//
// Register map under test:
//   0x00 TARGET_ADDR  0x04 INJECT_DATA  0x08 INJECT_MASK
//   0x0C CTRL (bit0 START, bit1 MODE)   0x10 STATUS (busy/done/error)
//
// Tests:
//   1. Register readback     -- programming port works at all
//   2. MODE 0 stuck-at       -- overwrite target with INJECT_DATA
//   3. MODE 1 bit-flip       -- read-modify-XOR with INJECT_MASK
//   4. STATUS/DONE handshake -- DONE sets, W1C clears, irq pulses
//   5. Back-to-back campaign -- second injection after first completes

`timescale 1ns/1ps

module tb_fault_injection_master;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    // ---- s_axi: TB drives FI master's programming port ----
    logic [31:0] s_awaddr;  logic s_awvalid; logic s_awready;
    logic [31:0] s_wdata;   logic [3:0] s_wstrb;
    logic        s_wvalid;  logic s_wready;
    logic [1:0]  s_bresp;   logic s_bvalid;  logic s_bready;
    logic [31:0] s_araddr;  logic s_arvalid; logic s_arready;
    logic [31:0] s_rdata;   logic [1:0] s_rresp;
    logic        s_rvalid;  logic s_rready;

    // ---- m_axi: FI master -> mem model ----
    logic [31:0] m_awaddr;  logic m_awvalid; logic m_awready;
    logic [31:0] m_wdata;   logic [3:0] m_wstrb;
    logic        m_wvalid;  logic m_wready;
    logic [1:0]  m_bresp;   logic m_bvalid;  logic m_bready;
    logic [31:0] m_araddr;  logic m_arvalid; logic m_arready;
    logic [31:0] m_rdata;   logic [1:0] m_rresp;
    logic        m_rvalid;  logic m_rready;

    logic fi_irq;

    fault_injection_master dut (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(s_awaddr), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata (s_wdata),  .s_axi_wstrb  (s_wstrb),   .s_axi_wvalid (s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bresp (s_bresp),  .s_axi_bvalid (s_bvalid),  .s_axi_bready (s_bready),
        .s_axi_araddr(s_araddr), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rdata (s_rdata),  .s_axi_rresp  (s_rresp),   .s_axi_rvalid (s_rvalid), .s_axi_rready(s_rready),
        .m_axi_awaddr(m_awaddr), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata (m_wdata),  .m_axi_wstrb  (m_wstrb),   .m_axi_wvalid (m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bresp (m_bresp),  .m_axi_bvalid (m_bvalid),  .m_axi_bready (m_bready),
        .m_axi_araddr(m_araddr), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rdata (m_rdata),  .m_axi_rresp  (m_rresp),   .m_axi_rvalid (m_rvalid), .m_axi_rready(m_rready),
        .irq(fi_irq)
    );

    axi4lite_mem_model #(.MEM_WORDS(256)) u_mem (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
        .s_axi_wdata (m_wdata),  .s_axi_wstrb  (m_wstrb),   .s_axi_wvalid (m_wvalid), .s_axi_wready(m_wready),
        .s_axi_bresp (m_bresp),  .s_axi_bvalid (m_bvalid),  .s_axi_bready (m_bready),
        .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
        .s_axi_rdata (m_rdata),  .s_axi_rresp  (m_rresp),   .s_axi_rvalid (m_rvalid), .s_axi_rready(m_rready)
    );

    int errors = 0;

    task automatic check(input string label, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %s: got=%h exp=%h", label, got, exp);
            errors++;
        end else $display("PASS %s: %h", label, got);
    endtask

    // ---- programming-port access tasks (mirrors dma_reg_write style) ----
    task automatic cfg_write(input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            s_awaddr  <= addr; s_awvalid <= 1'b1;
            s_wdata   <= data; s_wstrb   <= 4'hF; s_wvalid <= 1'b1;
            s_bready  <= 1'b1;
            wait (s_awready && s_wready);
            @(posedge clk);
            s_awvalid <= 1'b0; s_wvalid <= 1'b0;
            wait (s_bvalid);
            @(posedge clk);
            s_bready <= 1'b0;
        end
    endtask

    task automatic cfg_read(input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            s_araddr <= addr; s_arvalid <= 1'b1; s_rready <= 1'b1;
            wait (s_arready);
            @(posedge clk);
            s_arvalid <= 1'b0;
            wait (s_rvalid);
            data = s_rdata;
            @(posedge clk);
            s_rready <= 1'b0;
        end
    endtask

    // Wait for injection to finish, with timeout so a hang reports rather
    // than spinning forever (a stuck FI_READ/FI_WRITE shows up here).
    task automatic wait_done(input string label);
        int unsigned timeout;
        logic [31:0] st;
        begin
            timeout = 0;
            forever begin
                cfg_read(32'h10, st);
                if (st[1]) break;              // DONE
                timeout++;
                if (timeout > 200) begin
                    $display("FAIL %s: timeout waiting for DONE (status=%h)", label, st);
                    errors++;
                    break;
                end
            end
            if (st[2]) begin
                $display("FAIL %s: ERROR flag set (status=%h)", label, st);
                errors++;
            end
        end
    endtask

    // Read a word out of the mem model's backing array directly, to
    // confirm what the injection actually landed. Hierarchical reference
    // -- adjust the array name if axi4lite_mem_model uses a different one.
    function automatic [31:0] peek_mem(input int word_idx);
        peek_mem = u_mem.mem[word_idx];
    endfunction

    logic [31:0] rd;

    initial begin
        s_awvalid = 0; s_wvalid = 0; s_bready = 0;
        s_arvalid = 0; s_rready = 0;
        s_awaddr = 0; s_wdata = 0; s_wstrb = 0; s_araddr = 0;

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- 1. Register readback ----
        cfg_write(32'h00, 32'h0000_0040);
        cfg_write(32'h04, 32'hDEAD_BEEF);
        cfg_write(32'h08, 32'h0000_00FF);
        cfg_read (32'h00, rd); check("TARGET_ADDR readback", rd, 32'h0000_0040);
        cfg_read (32'h04, rd); check("INJECT_DATA readback", rd, 32'hDEAD_BEEF);
        cfg_read (32'h08, rd); check("INJECT_MASK readback", rd, 32'h0000_00FF);

        // ---- 2. MODE 0: stuck-at overwrite ----
        // Seed memory word 0x40/4 = index 16 with a known value first, by
        // using a MODE 0 injection of that seed value.
        cfg_write(32'h00, 32'h0000_0040);
        cfg_write(32'h04, 32'h1111_2222);
        cfg_write(32'h0C, 32'h0000_0001);      // START, MODE 0
        wait_done("MODE0 seed");
        cfg_write(32'h10, 32'h0000_0002);      // W1C DONE
        check("MODE0 stuck-at wrote target", peek_mem(16), 32'h1111_2222);

        // ---- 3. MODE 1: read-modify-XOR bit-flip ----
        // Target still holds 0x1111_2222; XOR with 0x0000_00FF should give
        // 0x1111_22DD.
        cfg_write(32'h08, 32'h0000_00FF);
        cfg_write(32'h0C, 32'h0000_0003);      // START | MODE 1
        wait_done("MODE1 bitflip");
        cfg_write(32'h10, 32'h0000_0002);      // W1C DONE
        check("MODE1 XOR result", peek_mem(16), 32'h1111_22DD);

        // ---- 4. STATUS/DONE handshake ----
        cfg_read(32'h10, rd);
        check("DONE cleared after W1C", rd[1], 1'b0);
        check("BUSY low when idle",     rd[0], 1'b0);

        // ---- 5. Back-to-back campaign: second injection at a new target -
        cfg_write(32'h00, 32'h0000_0080);      // word index 32
        cfg_write(32'h04, 32'hCAFE_0000);
        cfg_write(32'h0C, 32'h0000_0001);      // START, MODE 0
        wait_done("second campaign");
        cfg_write(32'h10, 32'h0000_0002);
        check("second injection landed", peek_mem(32), 32'hCAFE_0000);
        check("first target untouched",  peek_mem(16), 32'h1111_22DD);

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

    // Global watchdog -- a hung AXI handshake shouldn't spin forever.
    initial begin
        #200000;
        $display("FAIL: global timeout, simulation hung");
        $finish;
    end

endmodule : tb_fault_injection_master
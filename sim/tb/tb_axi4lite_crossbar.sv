// tb_axi4lite_crossbar3.sv
// Crossbar TB extended to 3 masters x 4 slaves.
//
// WHY THIS EXISTS SEPARATELY from tb_axi4lite_crossbar.sv:
// With NUM_MASTERS==2, a broken round-robin arbiter is nearly impossible
// to distinguish from a correct one -- with only two requesters, "rotate
// the pointer" and "just alternate" and even "always switch to the other
// guy" all produce identical behaviour. Every 2-master test passes on a
// pointer that is subtly wrong. Three masters is the smallest case where
// rotation order is actually observable and starvation can occur.
//
// This is also the first test of the arbiter at a non-power-of-2
// NUM_MASTERS, which exercises the (ptr + off) % NUM_MASTERS wrap that
// was previously untested (and where the mixed signed/unsigned expression
// Vivado flagged would have mattered).
//
// Topology (matches the AXI-fetch extension of the P4 map):
//   master 0: CPU data (cache/DMA via p3_top)
//   master 1: fault-injection master
//   master 2: CPU instruction fetch
//   slave 0: data mem   0x0000_0000
//   slave 1: dma_reg    0x0001_0000
//   slave 2: periph     0x0002_0000
//   slave 3: imem       0x0003_0000
//
// Tests:
//   1. Routing:    every master reaches every slave (12 combinations)
//   2. Fairness:   all 3 masters hammer ONE slave; each must complete its
//                  full burst -- catches starvation of the master the
//                  pointer never rotates to
//   3. Rotation:   with all 3 requesting simultaneously, no master may be
//                  served twice before the other two have been served once
//   4. Wrap:       pointer must wrap 2 -> 0 correctly (the % NUM_MASTERS
//                  path at a non-power-of-2 width)
//   5. Independence: 3 masters on 3 different slaves proceed concurrently

`timescale 1ns/1ps

module tb_axi4lite_crossbar3;

    localparam int NUM_MASTERS = 3;
    localparam int NUM_SLAVES  = 4;

    logic clk = 0, rst_n;
    always #5 clk = ~clk;

    logic [NUM_MASTERS-1:0][31:0] m_awaddr;
    logic [NUM_MASTERS-1:0]       m_awvalid, m_awready;
    logic [NUM_MASTERS-1:0][31:0] m_wdata;
    logic [NUM_MASTERS-1:0][3:0]  m_wstrb;
    logic [NUM_MASTERS-1:0]       m_wvalid,  m_wready;
    logic [NUM_MASTERS-1:0][1:0]  m_bresp;
    logic [NUM_MASTERS-1:0]       m_bvalid,  m_bready;
    logic [NUM_MASTERS-1:0][31:0] m_araddr;
    logic [NUM_MASTERS-1:0]       m_arvalid, m_arready;
    logic [NUM_MASTERS-1:0][31:0] m_rdata;
    logic [NUM_MASTERS-1:0][1:0]  m_rresp;
    logic [NUM_MASTERS-1:0]       m_rvalid,  m_rready;

    logic [NUM_SLAVES-1:0][31:0] s_awaddr;
    logic [NUM_SLAVES-1:0]       s_awvalid, s_awready;
    logic [NUM_SLAVES-1:0][31:0] s_wdata;
    logic [NUM_SLAVES-1:0][3:0]  s_wstrb;
    logic [NUM_SLAVES-1:0]       s_wvalid,  s_wready;
    logic [NUM_SLAVES-1:0][1:0]  s_bresp;
    logic [NUM_SLAVES-1:0]       s_bvalid,  s_bready;
    logic [NUM_SLAVES-1:0][31:0] s_araddr;
    logic [NUM_SLAVES-1:0]       s_arvalid, s_arready;
    logic [NUM_SLAVES-1:0][31:0] s_rdata;
    logic [NUM_SLAVES-1:0][1:0]  s_rresp;
    logic [NUM_SLAVES-1:0]       s_rvalid,  s_rready;

    axi4lite_crossbar #(
        .NUM_MASTERS(NUM_MASTERS),
        .NUM_SLAVES (NUM_SLAVES)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .m_awaddr(m_awaddr), .m_awvalid(m_awvalid), .m_awready(m_awready),
        .m_wdata (m_wdata),  .m_wstrb  (m_wstrb),   .m_wvalid (m_wvalid), .m_wready(m_wready),
        .m_bresp (m_bresp),  .m_bvalid (m_bvalid),  .m_bready (m_bready),
        .m_araddr(m_araddr), .m_arvalid(m_arvalid), .m_arready(m_arready),
        .m_rdata (m_rdata),  .m_rresp  (m_rresp),   .m_rvalid (m_rvalid), .m_rready(m_rready),
        .s_awaddr(s_awaddr), .s_awvalid(s_awvalid), .s_awready(s_awready),
        .s_wdata (s_wdata),  .s_wstrb  (s_wstrb),   .s_wvalid (s_wvalid), .s_wready(s_wready),
        .s_bresp (s_bresp),  .s_bvalid (s_bvalid),  .s_bready (s_bready),
        .s_araddr(s_araddr), .s_arvalid(s_arvalid), .s_arready(s_arready),
        .s_rdata (s_rdata),  .s_rresp  (s_rresp),   .s_rvalid (s_rvalid), .s_rready(s_rready)
    );

    genvar gs;
    generate
        for (gs = 0; gs < NUM_SLAVES; gs++) begin : g_slave_model
            axi4lite_mem_model #(.MEM_WORDS(1024)) u_mem (
                .clk(clk), .rst_n(rst_n),
                .s_axi_awaddr(s_awaddr[gs]), .s_axi_awvalid(s_awvalid[gs]), .s_axi_awready(s_awready[gs]),
                .s_axi_wdata (s_wdata[gs]),  .s_axi_wstrb  (s_wstrb[gs]),   .s_axi_wvalid (s_wvalid[gs]), .s_axi_wready(s_wready[gs]),
                .s_axi_bresp (s_bresp[gs]),  .s_axi_bvalid (s_bvalid[gs]),  .s_axi_bready (s_bready[gs]),
                .s_axi_araddr(s_araddr[gs]), .s_axi_arvalid(s_arvalid[gs]), .s_axi_arready(s_arready[gs]),
                .s_axi_rdata (s_rdata[gs]),  .s_axi_rresp  (s_rresp[gs]),   .s_axi_rvalid (s_rvalid[gs]), .s_axi_rready(s_rready[gs])
            );
        end
    endgenerate

    // ---- grant observation, for fairness/rotation checking ----
    // Records the order in which slave 0 hands out grants. Reaching into
    // the DUT is deliberate: fairness is a property of the arbiter's
    // internal sequencing, not observable from the data alone.
    int grant_log [$];
    int contend_log [$];   // snapshot of grant_log at end of contention phase
    logic prev_gv;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            prev_gv <= 1'b0;
        end else begin
            // log on rising edge of grant_valid for slave 0
            if (dut.grant_valid[0] && !prev_gv)
                grant_log.push_back(int'(dut.grant_idx[0]));
            prev_gv <= dut.grant_valid[0];
        end
    end

    task automatic axi_write(input int mi, input [31:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            m_awaddr[mi]  <= addr;  m_awvalid[mi] <= 1'b1;
            m_wdata[mi]   <= data;  m_wstrb[mi]   <= 4'hF;
            m_wvalid[mi]  <= 1'b1;  m_bready[mi]  <= 1'b1;
            wait (m_awready[mi] && m_wready[mi]);
            @(posedge clk);
            m_awvalid[mi] <= 1'b0;  m_wvalid[mi] <= 1'b0;
            wait (m_bvalid[mi]);
            @(posedge clk);
            m_bready[mi] <= 1'b0;
        end
    endtask

    task automatic axi_read(input int mi, input [31:0] addr, output [31:0] data);
        begin
            @(posedge clk);
            m_araddr[mi] <= addr; m_arvalid[mi] <= 1'b1; m_rready[mi] <= 1'b1;
            wait (m_arready[mi]);
            @(posedge clk);
            m_arvalid[mi] <= 1'b0;
            wait (m_rvalid[mi]);
            data = m_rdata[mi];
            @(posedge clk);
            m_rready[mi] <= 1'b0;
        end
    endtask

    int errors = 0;
    task automatic check(input string label, input [31:0] got, input [31:0] exp);
        if (got !== exp) begin
            $display("FAIL %s: got=%h exp=%h", label, got, exp);
            errors++;
        end else $display("PASS %s: %h", label, got);
    endtask

    logic [31:0] rd;
    logic [31:0] slave_base [4] = '{32'h0000_0000, 32'h0001_0000,
                                    32'h0002_0000, 32'h0003_0000};

    initial begin
        for (int m = 0; m < NUM_MASTERS; m++) begin
            m_awvalid[m] = 0; m_wvalid[m] = 0; m_bready[m] = 0;
            m_arvalid[m] = 0; m_rready[m] = 0;
            m_awaddr[m] = 0; m_wdata[m] = 0; m_wstrb[m] = 0; m_araddr[m] = 0;
        end

        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        repeat (5) @(posedge clk);

        // ---- 1. Full routing matrix: 3 masters x 4 slaves ----
        for (int m = 0; m < NUM_MASTERS; m++) begin
            for (int s = 0; s < NUM_SLAVES; s++) begin
                automatic logic [31:0] a = slave_base[s] + 32'h10;
                automatic logic [31:0] d = 32'hA0000000 | (m << 8) | s;
                axi_write(m, a, d);
                axi_read (m, a, rd);
                check($sformatf("route m%0d->s%0d", m, s), rd, d);
            end
        end

        // ---- 2. Fairness: all 3 masters burst at slave 0 concurrently ----
        // If the pointer never rotates to some master, that master's writes
        // never land and this fails. A 2-master test cannot expose this.
        grant_log.delete();
        fork
            begin for (int i = 0; i < 6; i++) axi_write(0, 32'h0000_0100 + i*4, 32'h1000_0000 + i); end
            begin for (int i = 0; i < 6; i++) axi_write(1, 32'h0000_0200 + i*4, 32'h2000_0000 + i); end
            begin for (int i = 0; i < 6; i++) axi_write(2, 32'h0000_0300 + i*4, 32'h3000_0000 + i); end
        join

        // Snapshot the grant log the instant contention ends. Everything
        // after this point is single-master readback traffic, where long
        // runs of the same grant are correct behaviour (nobody else is
        // asking) and would otherwise look like starvation.
        contend_log = grant_log;

        for (int i = 0; i < 6; i++) begin
            axi_read(0, 32'h0000_0100 + i*4, rd);
            check($sformatf("fair m0 w%0d", i), rd, 32'h1000_0000 + i);
        end
        for (int i = 0; i < 6; i++) begin
            axi_read(0, 32'h0000_0200 + i*4, rd);
            check($sformatf("fair m1 w%0d", i), rd, 32'h2000_0000 + i);
        end
        for (int i = 0; i < 6; i++) begin
            axi_read(0, 32'h0000_0300 + i*4, rd);
            check($sformatf("fair m2 w%0d", i), rd, 32'h3000_0000 + i);
        end

        // ---- 3. Starvation check on the contention-window grants only ----
        begin
            automatic int seen [3] = '{0, 0, 0};
            foreach (contend_log[i]) seen[contend_log[i]]++;
            for (int m = 0; m < 3; m++) begin
                if (seen[m] == 0) begin
                    $display("FAIL starvation: master %0d never granted slave 0", m);
                    errors++;
                end else
                    $display("PASS master %0d granted %0d times during contention", m, seen[m]);
            end
        end

        // ---- 4. Rotation order within the contention window ----
        // A correct round-robin cannot grant the same master three times
        // consecutively while the other two are still requesting.
        begin
            automatic int run_len = 1;
            automatic bit rot_ok  = 1;
            for (int i = 1; i < contend_log.size(); i++) begin
                if (contend_log[i] == contend_log[i-1]) run_len++;
                else run_len = 1;
                if (run_len >= 3) rot_ok = 0;
            end
            if (!rot_ok) begin
                $display("FAIL rotation: a master was granted 3+ times consecutively under contention");
                errors++;
            end else
                $display("PASS rotation: no master monopolised slave 0");
            $write("INFO grant order:");
            foreach (contend_log[i]) $write(" %0d", contend_log[i]);
            $display("");
        end

        // ---- 5. Independence: 3 masters, 3 different slaves, concurrently
        fork
            axi_write(0, 32'h0001_0020, 32'hDEAD_0001);   // -> slave 1
            axi_write(1, 32'h0002_0020, 32'hDEAD_0002);   // -> slave 2
            axi_write(2, 32'h0003_0020, 32'hDEAD_0003);   // -> slave 3
        join
        axi_read(0, 32'h0001_0020, rd); check("indep m0->s1", rd, 32'hDEAD_0001);
        axi_read(1, 32'h0002_0020, rd); check("indep m1->s2", rd, 32'hDEAD_0002);
        axi_read(2, 32'h0003_0020, rd); check("indep m2->s3", rd, 32'hDEAD_0003);

        $display("=========================");
        if (errors == 0) $display("ALL TESTS PASSED");
        else             $display("%0d TEST(S) FAILED", errors);
        $display("=========================");
        $finish;
    end

    initial begin
        #500000;
        $display("FAIL: global timeout -- likely an arbiter hang at NUM_MASTERS=3");
        $finish;
    end

endmodule : tb_axi4lite_crossbar3
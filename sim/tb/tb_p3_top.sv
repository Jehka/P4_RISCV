// tb_p3_top.sv
// MINERVA P3 testbench: exercises cache miss->allocate->hit, a dirty
// eviction/writeback, and a DMA memory-to-memory transfer, all through the
// arbiter onto one shared memory model.

`timescale 1ns/1ps

module tb_p3_top;

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  // CPU <-> cache
  logic         cpu_req_valid, cpu_req_ready, cpu_req_we;
  logic [31:0]  cpu_req_addr, cpu_req_wdata;
  logic [3:0]   cpu_req_be;
  logic         cpu_resp_valid;
  logic [31:0]  cpu_resp_rdata;

  // CPU <-> DMA regs
  logic [31:0] dr_awaddr, dr_wdata, dr_araddr, dr_rdata;
  logic [3:0]  dr_wstrb;
  logic [1:0]  dr_bresp, dr_rresp;
  logic        dr_awvalid, dr_awready, dr_wvalid, dr_wready, dr_bvalid, dr_bready;
  logic        dr_arvalid, dr_arready, dr_rvalid, dr_rready;
  logic        dma_irq;

  // p3_top <-> mem
  logic [31:0] m_awaddr, m_wdata, m_araddr, m_rdata;
  logic [3:0]  m_wstrb;
  logic [1:0]  m_bresp, m_rresp;
  logic        m_awvalid, m_awready, m_wvalid, m_wready, m_bvalid, m_bready;
  logic        m_arvalid, m_arready, m_rvalid, m_rready;

  p3_top dut (
      .clk(clk), .rst_n(rst_n),
      .cpu_req_valid(cpu_req_valid), .cpu_req_ready(cpu_req_ready),
      .cpu_req_addr(cpu_req_addr),   .cpu_req_wdata(cpu_req_wdata),
      .cpu_req_be(cpu_req_be),       .cpu_req_we(cpu_req_we),
      .cpu_resp_valid(cpu_resp_valid), .cpu_resp_rdata(cpu_resp_rdata),
      .dma_reg_awaddr(dr_awaddr), .dma_reg_awvalid(dr_awvalid), .dma_reg_awready(dr_awready),
      .dma_reg_wdata (dr_wdata),  .dma_reg_wstrb  (dr_wstrb),   .dma_reg_wvalid (dr_wvalid), .dma_reg_wready(dr_wready),
      .dma_reg_bresp (dr_bresp),  .dma_reg_bvalid (dr_bvalid),  .dma_reg_bready (dr_bready),
      .dma_reg_araddr(dr_araddr), .dma_reg_arvalid(dr_arvalid), .dma_reg_arready(dr_arready),
      .dma_reg_rdata (dr_rdata),  .dma_reg_rresp  (dr_rresp),   .dma_reg_rvalid (dr_rvalid), .dma_reg_rready(dr_rready),
      .dma_irq(dma_irq),
      .mem_awaddr(m_awaddr), .mem_awvalid(m_awvalid), .mem_awready(m_awready),
      .mem_wdata (m_wdata),  .mem_wstrb  (m_wstrb),   .mem_wvalid (m_wvalid), .mem_wready(m_wready),
      .mem_bresp (m_bresp),  .mem_bvalid (m_bvalid),  .mem_bready (m_bready),
      .mem_araddr(m_araddr), .mem_arvalid(m_arvalid), .mem_arready(m_arready),
      .mem_rdata (m_rdata),  .mem_rresp  (m_rresp),   .mem_rvalid (m_rvalid), .mem_rready(m_rready)
  );

  axi4lite_mem_model #(.MEM_WORDS(4096)) u_mem (
      .clk(clk), .rst_n(rst_n),
      .s_axi_awaddr(m_awaddr), .s_axi_awvalid(m_awvalid), .s_axi_awready(m_awready),
      .s_axi_wdata (m_wdata),  .s_axi_wstrb  (m_wstrb),   .s_axi_wvalid (m_wvalid), .s_axi_wready(m_wready),
      .s_axi_bresp (m_bresp),  .s_axi_bvalid (m_bvalid),  .s_axi_bready (m_bready),
      .s_axi_araddr(m_araddr), .s_axi_arvalid(m_arvalid), .s_axi_arready(m_arready),
      .s_axi_rdata (m_rdata),  .s_axi_rresp  (m_rresp),   .s_axi_rvalid (m_rvalid), .s_axi_rready(m_rready)
  );

  // ---------------- CPU-side task: single cache access ----------------
  task automatic cpu_access(input [31:0] addr, input [31:0] wdata, input we, input [3:0] be,
                             output [31:0] rdata);
    begin
      @(posedge clk);
      cpu_req_valid <= 1'b1;
      cpu_req_addr  <= addr;
      cpu_req_wdata <= wdata;
      cpu_req_we    <= we;
      cpu_req_be    <= be;
      wait (cpu_req_ready);
      @(posedge clk);
      cpu_req_valid <= 1'b0;
      wait (cpu_resp_valid);
      rdata = cpu_resp_rdata;
      @(posedge clk);
    end
  endtask

  // ---------------- DMA-side task: AXI4-Lite reg write/read ----------------
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

  task automatic dma_reg_read(input [7:0] off, output [31:0] data);
    begin
      @(posedge clk);
      dr_araddr  <= {24'd0, off};
      dr_arvalid <= 1'b1;
      dr_rready  <= 1'b1;
      wait (dr_arready);
      @(posedge clk);
      dr_arvalid <= 1'b0;
      wait (dr_rvalid);
      data = dr_rdata;
      @(posedge clk);
      dr_rready <= 1'b0;
    end
  endtask

  logic [31:0] rd;
  int errors = 0;

  initial begin
    cpu_req_valid = 0; cpu_req_we = 0; cpu_req_be = 4'hF;
    dr_awvalid = 0; dr_wvalid = 0; dr_bready = 0; dr_arvalid = 0; dr_rready = 0;
    rst_n = 0;
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (2) @(posedge clk);

    // Pre-load memory word 0x100 via backdoor for a known read-miss value
    u_mem.mem[32'h100 >> 2] = 32'hCAFEBABE;

    // --- Test 1: read miss -> allocate -> hit, expect CAFEBABE ---
    cpu_access(32'h100, 32'h0, 1'b0, 4'hF, rd);
    if (rd !== 32'hCAFEBABE) begin
      $display("FAIL T1 read-miss: got %h expected CAFEBABE", rd);
      errors++;
    end else $display("PASS T1 read-miss allocate: %h", rd);

    // --- Test 2: same addr again -> should hit immediately, same data ---
    cpu_access(32'h100, 32'h0, 1'b0, 4'hF, rd);
    if (rd !== 32'hCAFEBABE) begin
      $display("FAIL T2 read-hit: got %h", rd);
      errors++;
    end else $display("PASS T2 read-hit: %h", rd);

    // --- Test 3: write hit, dirty the line ---
    cpu_access(32'h100, 32'hDEADBEEF, 1'b1, 4'hF, rd);
    cpu_access(32'h100, 32'h0, 1'b0, 4'hF, rd);
    if (rd !== 32'hDEADBEEF) begin
      $display("FAIL T3 write-hit readback: got %h", rd);
      errors++;
    end else $display("PASS T3 write-hit readback: %h", rd);

    // --- Test 4: force eviction by accessing a different address with same
    // index (index bits [11:4]; +0x1000 keeps index, changes tag) ---
    cpu_access(32'h1100, 32'h0, 1'b0, 4'hF, rd); // triggers writeback of 0x100's line + allocate
    cpu_access(32'h100, 32'h0, 1'b0, 4'hF, rd);  // re-fetch evicted line from mem
    if (rd !== 32'hDEADBEEF) begin
      $display("FAIL T4 writeback/re-fetch: got %h expected DEADBEEF (writeback lost data)", rd);
      errors++;
    end else $display("PASS T4 writeback+refetch: %h", rd);

    // --- Test 5: DMA transfer 16 bytes from 0x200 to 0x300 ---
    u_mem.mem[32'h200>>2] = 32'h11111111;
    u_mem.mem[32'h204>>2] = 32'h22222222;
    u_mem.mem[32'h208>>2] = 32'h33333333;
    u_mem.mem[32'h20C>>2] = 32'h44444444;

    dma_reg_write(8'h00, 32'h200); // SRC
    dma_reg_write(8'h04, 32'h300); // DST
    dma_reg_write(8'h08, 32'd16);  // LEN
    dma_reg_write(8'h0C, 32'h1);   // START

    wait (dma_irq);
    @(posedge clk);

    if (u_mem.mem[32'h300>>2] !== 32'h11111111 ||
        u_mem.mem[32'h304>>2] !== 32'h22222222 ||
        u_mem.mem[32'h308>>2] !== 32'h33333333 ||
        u_mem.mem[32'h30C>>2] !== 32'h44444444) begin
      $display("FAIL T5 DMA transfer mismatch: %h %h %h %h",
                u_mem.mem[32'h300>>2], u_mem.mem[32'h304>>2],
                u_mem.mem[32'h308>>2], u_mem.mem[32'h30C>>2]);
      errors++;
    end else $display("PASS T5 DMA transfer");

    dma_reg_read(8'h10, rd);
    if (rd[0] !== 1'b0 || rd[1] !== 1'b1) begin
      $display("FAIL T5b DMA status: %h (expect busy=0 done=1)", rd);
      errors++;
    end else $display("PASS T5b DMA status: %h", rd);

    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d TEST(S) FAILED", errors);

    $finish;
  end

  initial begin
    #20000;
    $display("TIMEOUT");
    $finish;
  end

endmodule : tb_p3_top
// p3_top.sv
// MINERVA P3 top level: Cache Controller + DMA Engine, arbitrated onto one
// external AXI4-Lite memory port. This is the unit that plugs into P4's
// crossbar as a single AXI4-Lite slave (CPU->cache, CPU->DMA regs) and
// master (shared memory port).

`include "axi4lite_ports.vh"

module p3_top (
    input  logic clk,
    input  logic rst_n,

    // CPU side: cache data/instruction access (from P2 MEM stage)
    input  logic         cpu_req_valid,
    output logic         cpu_req_ready,
    input  logic [31:0]  cpu_req_addr,
    input  logic [31:0]  cpu_req_wdata,
    input  logic [3:0]   cpu_req_be,
    input  logic         cpu_req_we,
    output logic         cpu_resp_valid,
    output logic [31:0]  cpu_resp_rdata,

    // CPU side: DMA register programming (AXI4-Lite slave)
    `AXI4LITE_SLAVE_PORTS(dma_reg),

    output logic          dma_irq,

    // External shared memory (AXI4-Lite master)
    `AXI4LITE_MASTER_PORTS(mem)
);

  // internal AXI4-Lite links: cache<->arb, dma<->arb
  wire [31:0] c_awaddr, c_wdata, c_araddr, c_rdata;
  wire [3:0]  c_wstrb;
  wire [1:0]  c_bresp, c_rresp;
  wire        c_awvalid, c_awready, c_wvalid, c_wready, c_bvalid, c_bready;
  wire        c_arvalid, c_arready, c_rvalid, c_rready;

  wire [31:0] d_awaddr, d_wdata, d_araddr, d_rdata;
  wire [3:0]  d_wstrb;
  wire [1:0]  d_bresp, d_rresp;
  wire        d_awvalid, d_awready, d_wvalid, d_wready, d_bvalid, d_bready;
  wire        d_arvalid, d_arready, d_rvalid, d_rready;

  cache_controller u_cache (
      .clk (clk), .rst_n (rst_n),
      .cpu_req_valid (cpu_req_valid), .cpu_req_ready (cpu_req_ready),
      .cpu_req_addr  (cpu_req_addr),  .cpu_req_wdata (cpu_req_wdata),
      .cpu_req_be    (cpu_req_be),    .cpu_req_we    (cpu_req_we),
      .cpu_resp_valid(cpu_resp_valid),.cpu_resp_rdata(cpu_resp_rdata),
      .m_axi_awaddr(c_awaddr), .m_axi_awvalid(c_awvalid), .m_axi_awready(c_awready),
      .m_axi_wdata (c_wdata),  .m_axi_wstrb  (c_wstrb),   .m_axi_wvalid (c_wvalid), .m_axi_wready(c_wready),
      .m_axi_bresp (c_bresp),  .m_axi_bvalid (c_bvalid),  .m_axi_bready (c_bready),
      .m_axi_araddr(c_araddr), .m_axi_arvalid(c_arvalid), .m_axi_arready(c_arready),
      .m_axi_rdata (c_rdata),  .m_axi_rresp  (c_rresp),   .m_axi_rvalid (c_rvalid), .m_axi_rready(c_rready)
  );

  dma_engine u_dma (
      .clk (clk), .rst_n (rst_n),
      .s_axi_awaddr(dma_reg_awaddr), .s_axi_awvalid(dma_reg_awvalid), .s_axi_awready(dma_reg_awready),
      .s_axi_wdata (dma_reg_wdata),  .s_axi_wstrb  (dma_reg_wstrb),   .s_axi_wvalid (dma_reg_wvalid), .s_axi_wready(dma_reg_wready),
      .s_axi_bresp (dma_reg_bresp),  .s_axi_bvalid (dma_reg_bvalid),  .s_axi_bready (dma_reg_bready),
      .s_axi_araddr(dma_reg_araddr), .s_axi_arvalid(dma_reg_arvalid), .s_axi_arready(dma_reg_arready),
      .s_axi_rdata (dma_reg_rdata),  .s_axi_rresp  (dma_reg_rresp),   .s_axi_rvalid (dma_reg_rvalid), .s_axi_rready(dma_reg_rready),
      .m_axi_awaddr(d_awaddr), .m_axi_awvalid(d_awvalid), .m_axi_awready(d_awready),
      .m_axi_wdata (d_wdata),  .m_axi_wstrb  (d_wstrb),   .m_axi_wvalid (d_wvalid), .m_axi_wready(d_wready),
      .m_axi_bresp (d_bresp),  .m_axi_bvalid (d_bvalid),  .m_axi_bready (d_bready),
      .m_axi_araddr(d_araddr), .m_axi_arvalid(d_arvalid), .m_axi_arready(d_arready),
      .m_axi_rdata (d_rdata),  .m_axi_rresp  (d_rresp),   .m_axi_rvalid (d_rvalid), .m_axi_rready(d_rready),
      .irq (dma_irq)
  );

  cache_dma_arbiter u_arb (
      .clk (clk), .rst_n (rst_n),
      .cache_awaddr(c_awaddr), .cache_awvalid(c_awvalid), .cache_awready(c_awready),
      .cache_wdata (c_wdata),  .cache_wstrb  (c_wstrb),   .cache_wvalid (c_wvalid), .cache_wready(c_wready),
      .cache_bresp (c_bresp),  .cache_bvalid (c_bvalid),  .cache_bready (c_bready),
      .cache_araddr(c_araddr), .cache_arvalid(c_arvalid), .cache_arready(c_arready),
      .cache_rdata (c_rdata),  .cache_rresp  (c_rresp),   .cache_rvalid (c_rvalid), .cache_rready(c_rready),
      .dma_awaddr(d_awaddr), .dma_awvalid(d_awvalid), .dma_awready(d_awready),
      .dma_wdata (d_wdata),  .dma_wstrb  (d_wstrb),   .dma_wvalid (d_wvalid), .dma_wready(d_wready),
      .dma_bresp (d_bresp),  .dma_bvalid (d_bvalid),  .dma_bready (d_bready),
      .dma_araddr(d_araddr), .dma_arvalid(d_arvalid), .dma_arready(d_arready),
      .dma_rdata (d_rdata),  .dma_rresp  (d_rresp),   .dma_rvalid (d_rvalid), .dma_rready(d_rready),
      .mem_awaddr(mem_awaddr), .mem_awvalid(mem_awvalid), .mem_awready(mem_awready),
      .mem_wdata (mem_wdata),  .mem_wstrb  (mem_wstrb),   .mem_wvalid (mem_wvalid), .mem_wready(mem_wready),
      .mem_bresp (mem_bresp),  .mem_bvalid (mem_bvalid),  .mem_bready (mem_bready),
      .mem_araddr(mem_araddr), .mem_arvalid(mem_arvalid), .mem_arready(mem_arready),
      .mem_rdata (mem_rdata),  .mem_rresp  (mem_rresp),   .mem_rvalid (mem_rvalid), .mem_rready(mem_rready)
  );

endmodule : p3_top
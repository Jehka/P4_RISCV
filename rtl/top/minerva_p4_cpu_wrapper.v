// minerva_p4_cpu_wrapper.v
// Plain-Verilog IPI wrapper around riscv_cpu_p4.
//
// Replaces minerva_p2p3_wrapper.v for the P4 configuration. Two changes
// versus that file:
//   - wraps riscv_cpu_p4 (AXI instruction fetch) instead of riscv_cpu_p3
//   - exposes the new instr_mem master port and if_stall_out
// dma_reg is exposed as real ports (as in v3), NOT tied off: it must
// reach crossbar slave 1 so any master can program the DMA engine.
//
// riscv_cpu_p4's ports are already flat (axi4lite_ports.vh macros); this
// wrapper exists because the module body is SystemVerilog, which IPI
// cannot take as a block directly.

module minerva_p4_cpu_wrapper (
    input  wire        clk,
    input  wire        rst,            // ACTIVE HIGH

    output wire [31:0] debug_out,
    output wire        mem_stall_out,
    output wire        if_stall_out,
    output wire [31:0] if_pc_out,
    output wire        dma_irq,

    // ---- dma_reg: AXI4-Lite SLAVE, from crossbar slave 1 ----
    input  wire [31:0] dma_reg_awaddr,
    input  wire dma_reg_awvalid,
    output wire dma_reg_awready,
    input  wire [31:0] dma_reg_wdata,
    input  wire [3:0] dma_reg_wstrb,
    input  wire dma_reg_wvalid,
    output wire dma_reg_wready,
    output wire [1:0] dma_reg_bresp,
    output wire dma_reg_bvalid,
    input  wire dma_reg_bready,
    input  wire [31:0] dma_reg_araddr,
    input  wire dma_reg_arvalid,
    output wire dma_reg_arready,
    output wire [31:0] dma_reg_rdata,
    output wire [1:0] dma_reg_rresp,
    output wire dma_reg_rvalid,
    input  wire dma_reg_rready,

    // ---- ext_mem: AXI4-Lite MASTER, to crossbar master 0 (data) ----
    output wire [31:0] ext_mem_awaddr,
    output wire ext_mem_awvalid,
    input  wire ext_mem_awready,
    output wire [31:0] ext_mem_wdata,
    output wire [3:0] ext_mem_wstrb,
    output wire ext_mem_wvalid,
    input  wire ext_mem_wready,
    input  wire [1:0] ext_mem_bresp,
    input  wire ext_mem_bvalid,
    output wire ext_mem_bready,
    output wire [31:0] ext_mem_araddr,
    output wire ext_mem_arvalid,
    input  wire ext_mem_arready,
    input  wire [31:0] ext_mem_rdata,
    input  wire [1:0] ext_mem_rresp,
    input  wire ext_mem_rvalid,
    output wire ext_mem_rready,

    // ---- instr_mem: AXI4-Lite MASTER, to crossbar master 2 (fetch) ----
    output wire [31:0] instr_mem_awaddr,
    output wire instr_mem_awvalid,
    input  wire instr_mem_awready,
    output wire [31:0] instr_mem_wdata,
    output wire [3:0] instr_mem_wstrb,
    output wire instr_mem_wvalid,
    input  wire instr_mem_wready,
    input  wire [1:0] instr_mem_bresp,
    input  wire instr_mem_bvalid,
    output wire instr_mem_bready,
    output wire [31:0] instr_mem_araddr,
    output wire instr_mem_arvalid,
    input  wire instr_mem_arready,
    input  wire [31:0] instr_mem_rdata,
    input  wire [1:0] instr_mem_rresp,
    input  wire instr_mem_rvalid,
    output wire instr_mem_rready
);

    riscv_cpu_p4 #(.IMEM_BASE(32'h0003_0000)) u_cpu (
        .clk (clk),
        .rst (rst),
        .debug_out     (debug_out),
        .mem_stall_out (mem_stall_out),
        .if_stall_out  (if_stall_out),
        .if_pc_out     (if_pc_out),
        .dma_irq       (dma_irq),

        .dma_reg_awaddr  (dma_reg_awaddr),
        .dma_reg_awvalid (dma_reg_awvalid),
        .dma_reg_awready (dma_reg_awready),
        .dma_reg_wdata   (dma_reg_wdata),
        .dma_reg_wstrb   (dma_reg_wstrb),
        .dma_reg_wvalid  (dma_reg_wvalid),
        .dma_reg_wready  (dma_reg_wready),
        .dma_reg_bresp   (dma_reg_bresp),
        .dma_reg_bvalid  (dma_reg_bvalid),
        .dma_reg_bready  (dma_reg_bready),
        .dma_reg_araddr  (dma_reg_araddr),
        .dma_reg_arvalid (dma_reg_arvalid),
        .dma_reg_arready (dma_reg_arready),
        .dma_reg_rdata   (dma_reg_rdata),
        .dma_reg_rresp   (dma_reg_rresp),
        .dma_reg_rvalid  (dma_reg_rvalid),
        .dma_reg_rready  (dma_reg_rready),

        .ext_mem_awaddr  (ext_mem_awaddr),
        .ext_mem_awvalid (ext_mem_awvalid),
        .ext_mem_awready (ext_mem_awready),
        .ext_mem_wdata   (ext_mem_wdata),
        .ext_mem_wstrb   (ext_mem_wstrb),
        .ext_mem_wvalid  (ext_mem_wvalid),
        .ext_mem_wready  (ext_mem_wready),
        .ext_mem_bresp   (ext_mem_bresp),
        .ext_mem_bvalid  (ext_mem_bvalid),
        .ext_mem_bready  (ext_mem_bready),
        .ext_mem_araddr  (ext_mem_araddr),
        .ext_mem_arvalid (ext_mem_arvalid),
        .ext_mem_arready (ext_mem_arready),
        .ext_mem_rdata   (ext_mem_rdata),
        .ext_mem_rresp   (ext_mem_rresp),
        .ext_mem_rvalid  (ext_mem_rvalid),
        .ext_mem_rready  (ext_mem_rready),

        .instr_mem_awaddr  (instr_mem_awaddr),
        .instr_mem_awvalid (instr_mem_awvalid),
        .instr_mem_awready (instr_mem_awready),
        .instr_mem_wdata   (instr_mem_wdata),
        .instr_mem_wstrb   (instr_mem_wstrb),
        .instr_mem_wvalid  (instr_mem_wvalid),
        .instr_mem_wready  (instr_mem_wready),
        .instr_mem_bresp   (instr_mem_bresp),
        .instr_mem_bvalid  (instr_mem_bvalid),
        .instr_mem_bready  (instr_mem_bready),
        .instr_mem_araddr  (instr_mem_araddr),
        .instr_mem_arvalid (instr_mem_arvalid),
        .instr_mem_arready (instr_mem_arready),
        .instr_mem_rdata   (instr_mem_rdata),
        .instr_mem_rresp   (instr_mem_rresp),
        .instr_mem_rvalid  (instr_mem_rvalid),
        .instr_mem_rready  (instr_mem_rready)
    );

endmodule
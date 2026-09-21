// p4_top.v  (P4 + AXI instruction fetch)
//
// System-level top. Plain Verilog for Vivado IP Integrator.
//
// Topology:
//   crossbar m0 <- CPU ext_mem      (data: cache + DMA)
//   crossbar m1 <- fault_injection_master m_axi
//   crossbar m2 <- CPU instr_mem    (AXI instruction fetch)
//   crossbar s0 -> ext_mem_*        exits -> AXI BRAM Controller (data)
//   crossbar s1 -> CPU dma_reg      internal loopback
//   crossbar s2 -> periph_*         exits (reserved -- MUST be tied off)
//   crossbar s3 -> imem_*           exits -> AXI BRAM Controller (instr)
//
// WHY s3 MATTERS: instruction memory is now an addressable slave, so the
// fault-injection master on m1 can corrupt INSTRUCTIONS, not just data,
// and programs can be loaded at runtime over JTAG instead of being baked
// into the bitstream. That was the entire point of the fetch change.
//
// RESET: this module takes ACTIVE-HIGH rst (matching riscv_cpu_p4 and the
// P3 block design). It is inverted exactly once here and distributed as
// rst_n. Still check every Xilinx IP in the BD with
// get_property CONFIG.C_*_RESET_HIGH -- this only fixes polarity INSIDE
// p4_top.
//
// PERIPH WARNING: if s2 is left dangling in the BD, any access into
// 0x0002_xxxx holds the crossbar's grant forever and wedges the fabric.
// Tie periph_*ready high and periph_*valid low until something real is
// attached.

module p4_top (
    input  wire        clk,
    input  wire        rst,            // ACTIVE HIGH

    output wire [31:0] debug_out,
    output wire        mem_stall_out,
    output wire        if_stall_out,
    output wire [31:0] if_pc_out,
    output wire        dma_irq,
    output wire        fi_irq,

    // ---- Slave 0: data memory -> AXI BRAM Controller ----
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

    // ---- Slave 2: reserved peripheral (tie off in the BD) ----
    output wire [31:0] periph_awaddr,
    output wire periph_awvalid,
    input  wire periph_awready,
    output wire [31:0] periph_wdata,
    output wire [3:0] periph_wstrb,
    output wire periph_wvalid,
    input  wire periph_wready,
    input  wire [1:0] periph_bresp,
    input  wire periph_bvalid,
    output wire periph_bready,
    output wire [31:0] periph_araddr,
    output wire periph_arvalid,
    input  wire periph_arready,
    input  wire [31:0] periph_rdata,
    input  wire [1:0] periph_rresp,
    input  wire periph_rvalid,
    output wire periph_rready,

    // ---- Slave 3: instruction memory -> AXI BRAM Controller ----
    output wire [31:0] imem_awaddr,
    output wire imem_awvalid,
    input  wire imem_awready,
    output wire [31:0] imem_wdata,
    output wire [3:0] imem_wstrb,
    output wire imem_wvalid,
    input  wire imem_wready,
    input  wire [1:0] imem_bresp,
    input  wire imem_bvalid,
    output wire imem_bready,
    output wire [31:0] imem_araddr,
    output wire imem_arvalid,
    input  wire imem_arready,
    input  wire [31:0] imem_rdata,
    input  wire [1:0] imem_rresp,
    input  wire imem_rvalid,
    output wire imem_rready,

    // ---- Fault-injection programming port (from PS or pins) ----
    input  wire [31:0] fi_cfg_awaddr,
    input  wire fi_cfg_awvalid,
    output wire fi_cfg_awready,
    input  wire [31:0] fi_cfg_wdata,
    input  wire [3:0] fi_cfg_wstrb,
    input  wire fi_cfg_wvalid,
    output wire fi_cfg_wready,
    output wire [1:0] fi_cfg_bresp,
    output wire fi_cfg_bvalid,
    input  wire fi_cfg_bready,
    input  wire [31:0] fi_cfg_araddr,
    input  wire fi_cfg_arvalid,
    output wire fi_cfg_arready,
    output wire [31:0] fi_cfg_rdata,
    output wire [1:0] fi_cfg_rresp,
    output wire fi_cfg_rvalid,
    input  wire fi_cfg_rready
);

    // Single inversion point for the active-high -> active-low boundary.
    wire rst_n = ~rst;

    // ---- internal master/slave nets ----
    wire [31:0] cpu_d_awaddr;
    wire cpu_d_awvalid;
    wire cpu_d_awready;
    wire [31:0] cpu_d_wdata;
    wire [3:0] cpu_d_wstrb;
    wire cpu_d_wvalid;
    wire cpu_d_wready;
    wire [1:0] cpu_d_bresp;
    wire cpu_d_bvalid;
    wire cpu_d_bready;
    wire [31:0] cpu_d_araddr;
    wire cpu_d_arvalid;
    wire cpu_d_arready;
    wire [31:0] cpu_d_rdata;
    wire [1:0] cpu_d_rresp;
    wire cpu_d_rvalid;
    wire cpu_d_rready;

    wire [31:0] fi_m_awaddr;
    wire fi_m_awvalid;
    wire fi_m_awready;
    wire [31:0] fi_m_wdata;
    wire [3:0] fi_m_wstrb;
    wire fi_m_wvalid;
    wire fi_m_wready;
    wire [1:0] fi_m_bresp;
    wire fi_m_bvalid;
    wire fi_m_bready;
    wire [31:0] fi_m_araddr;
    wire fi_m_arvalid;
    wire fi_m_arready;
    wire [31:0] fi_m_rdata;
    wire [1:0] fi_m_rresp;
    wire fi_m_rvalid;
    wire fi_m_rready;

    wire [31:0] cpu_i_awaddr;
    wire cpu_i_awvalid;
    wire cpu_i_awready;
    wire [31:0] cpu_i_wdata;
    wire [3:0] cpu_i_wstrb;
    wire cpu_i_wvalid;
    wire cpu_i_wready;
    wire [1:0] cpu_i_bresp;
    wire cpu_i_bvalid;
    wire cpu_i_bready;
    wire [31:0] cpu_i_araddr;
    wire cpu_i_arvalid;
    wire cpu_i_arready;
    wire [31:0] cpu_i_rdata;
    wire [1:0] cpu_i_rresp;
    wire cpu_i_rvalid;
    wire cpu_i_rready;

    wire [31:0] dma_reg_awaddr;
    wire dma_reg_awvalid;
    wire dma_reg_awready;
    wire [31:0] dma_reg_wdata;
    wire [3:0] dma_reg_wstrb;
    wire dma_reg_wvalid;
    wire dma_reg_wready;
    wire [1:0] dma_reg_bresp;
    wire dma_reg_bvalid;
    wire dma_reg_bready;
    wire [31:0] dma_reg_araddr;
    wire dma_reg_arvalid;
    wire dma_reg_arready;
    wire [31:0] dma_reg_rdata;
    wire [1:0] dma_reg_rresp;
    wire dma_reg_rvalid;
    wire dma_reg_rready;

    // ================= CPU (pipeline + cache + DMA) =================
    minerva_p4_cpu_wrapper u_cpu (
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

        .ext_mem_awaddr  (cpu_d_awaddr),
        .ext_mem_awvalid (cpu_d_awvalid),
        .ext_mem_awready (cpu_d_awready),
        .ext_mem_wdata   (cpu_d_wdata),
        .ext_mem_wstrb   (cpu_d_wstrb),
        .ext_mem_wvalid  (cpu_d_wvalid),
        .ext_mem_wready  (cpu_d_wready),
        .ext_mem_bresp   (cpu_d_bresp),
        .ext_mem_bvalid  (cpu_d_bvalid),
        .ext_mem_bready  (cpu_d_bready),
        .ext_mem_araddr  (cpu_d_araddr),
        .ext_mem_arvalid (cpu_d_arvalid),
        .ext_mem_arready (cpu_d_arready),
        .ext_mem_rdata   (cpu_d_rdata),
        .ext_mem_rresp   (cpu_d_rresp),
        .ext_mem_rvalid  (cpu_d_rvalid),
        .ext_mem_rready  (cpu_d_rready),

        .instr_mem_awaddr  (cpu_i_awaddr),
        .instr_mem_awvalid (cpu_i_awvalid),
        .instr_mem_awready (cpu_i_awready),
        .instr_mem_wdata   (cpu_i_wdata),
        .instr_mem_wstrb   (cpu_i_wstrb),
        .instr_mem_wvalid  (cpu_i_wvalid),
        .instr_mem_wready  (cpu_i_wready),
        .instr_mem_bresp   (cpu_i_bresp),
        .instr_mem_bvalid  (cpu_i_bvalid),
        .instr_mem_bready  (cpu_i_bready),
        .instr_mem_araddr  (cpu_i_araddr),
        .instr_mem_arvalid (cpu_i_arvalid),
        .instr_mem_arready (cpu_i_arready),
        .instr_mem_rdata   (cpu_i_rdata),
        .instr_mem_rresp   (cpu_i_rresp),
        .instr_mem_rvalid  (cpu_i_rvalid),
        .instr_mem_rready  (cpu_i_rready)
    );

    // ================= Fault-injection master =================
    fault_injection_master_wrapper u_fi (
        .clk   (clk),
        .rst_n (rst_n),

        .s_axi_awaddr  (fi_cfg_awaddr),
        .s_axi_awvalid (fi_cfg_awvalid),
        .s_axi_awready (fi_cfg_awready),
        .s_axi_wdata   (fi_cfg_wdata),
        .s_axi_wstrb   (fi_cfg_wstrb),
        .s_axi_wvalid  (fi_cfg_wvalid),
        .s_axi_wready  (fi_cfg_wready),
        .s_axi_bresp   (fi_cfg_bresp),
        .s_axi_bvalid  (fi_cfg_bvalid),
        .s_axi_bready  (fi_cfg_bready),
        .s_axi_araddr  (fi_cfg_araddr),
        .s_axi_arvalid (fi_cfg_arvalid),
        .s_axi_arready (fi_cfg_arready),
        .s_axi_rdata   (fi_cfg_rdata),
        .s_axi_rresp   (fi_cfg_rresp),
        .s_axi_rvalid  (fi_cfg_rvalid),
        .s_axi_rready  (fi_cfg_rready),

        .m_axi_awaddr  (fi_m_awaddr),
        .m_axi_awvalid (fi_m_awvalid),
        .m_axi_awready (fi_m_awready),
        .m_axi_wdata   (fi_m_wdata),
        .m_axi_wstrb   (fi_m_wstrb),
        .m_axi_wvalid  (fi_m_wvalid),
        .m_axi_wready  (fi_m_wready),
        .m_axi_bresp   (fi_m_bresp),
        .m_axi_bvalid  (fi_m_bvalid),
        .m_axi_bready  (fi_m_bready),
        .m_axi_araddr  (fi_m_araddr),
        .m_axi_arvalid (fi_m_arvalid),
        .m_axi_arready (fi_m_arready),
        .m_axi_rdata   (fi_m_rdata),
        .m_axi_rresp   (fi_m_rresp),
        .m_axi_rvalid  (fi_m_rvalid),
        .m_axi_rready  (fi_m_rready),
        .irq (fi_irq)
    );

    // ================= Crossbar fabric =================
    axi4lite_crossbar_wrapper u_xbar (
        .clk   (clk),
        .rst_n (rst_n),

        // master 0
        .m0_awaddr  (cpu_d_awaddr),
        .m0_awvalid (cpu_d_awvalid),
        .m0_awready (cpu_d_awready),
        .m0_wdata   (cpu_d_wdata),
        .m0_wstrb   (cpu_d_wstrb),
        .m0_wvalid  (cpu_d_wvalid),
        .m0_wready  (cpu_d_wready),
        .m0_bresp   (cpu_d_bresp),
        .m0_bvalid  (cpu_d_bvalid),
        .m0_bready  (cpu_d_bready),
        .m0_araddr  (cpu_d_araddr),
        .m0_arvalid (cpu_d_arvalid),
        .m0_arready (cpu_d_arready),
        .m0_rdata   (cpu_d_rdata),
        .m0_rresp   (cpu_d_rresp),
        .m0_rvalid  (cpu_d_rvalid),
        .m0_rready  (cpu_d_rready),

        // master 1
        .m1_awaddr  (fi_m_awaddr),
        .m1_awvalid (fi_m_awvalid),
        .m1_awready (fi_m_awready),
        .m1_wdata   (fi_m_wdata),
        .m1_wstrb   (fi_m_wstrb),
        .m1_wvalid  (fi_m_wvalid),
        .m1_wready  (fi_m_wready),
        .m1_bresp   (fi_m_bresp),
        .m1_bvalid  (fi_m_bvalid),
        .m1_bready  (fi_m_bready),
        .m1_araddr  (fi_m_araddr),
        .m1_arvalid (fi_m_arvalid),
        .m1_arready (fi_m_arready),
        .m1_rdata   (fi_m_rdata),
        .m1_rresp   (fi_m_rresp),
        .m1_rvalid  (fi_m_rvalid),
        .m1_rready  (fi_m_rready),

        // master 2
        .m2_awaddr  (cpu_i_awaddr),
        .m2_awvalid (cpu_i_awvalid),
        .m2_awready (cpu_i_awready),
        .m2_wdata   (cpu_i_wdata),
        .m2_wstrb   (cpu_i_wstrb),
        .m2_wvalid  (cpu_i_wvalid),
        .m2_wready  (cpu_i_wready),
        .m2_bresp   (cpu_i_bresp),
        .m2_bvalid  (cpu_i_bvalid),
        .m2_bready  (cpu_i_bready),
        .m2_araddr  (cpu_i_araddr),
        .m2_arvalid (cpu_i_arvalid),
        .m2_arready (cpu_i_arready),
        .m2_rdata   (cpu_i_rdata),
        .m2_rresp   (cpu_i_rresp),
        .m2_rvalid  (cpu_i_rvalid),
        .m2_rready  (cpu_i_rready),

        // slave 0
        .s0_awaddr  (ext_mem_awaddr),
        .s0_awvalid (ext_mem_awvalid),
        .s0_awready (ext_mem_awready),
        .s0_wdata   (ext_mem_wdata),
        .s0_wstrb   (ext_mem_wstrb),
        .s0_wvalid  (ext_mem_wvalid),
        .s0_wready  (ext_mem_wready),
        .s0_bresp   (ext_mem_bresp),
        .s0_bvalid  (ext_mem_bvalid),
        .s0_bready  (ext_mem_bready),
        .s0_araddr  (ext_mem_araddr),
        .s0_arvalid (ext_mem_arvalid),
        .s0_arready (ext_mem_arready),
        .s0_rdata   (ext_mem_rdata),
        .s0_rresp   (ext_mem_rresp),
        .s0_rvalid  (ext_mem_rvalid),
        .s0_rready  (ext_mem_rready),

        // slave 1
        .s1_awaddr  (dma_reg_awaddr),
        .s1_awvalid (dma_reg_awvalid),
        .s1_awready (dma_reg_awready),
        .s1_wdata   (dma_reg_wdata),
        .s1_wstrb   (dma_reg_wstrb),
        .s1_wvalid  (dma_reg_wvalid),
        .s1_wready  (dma_reg_wready),
        .s1_bresp   (dma_reg_bresp),
        .s1_bvalid  (dma_reg_bvalid),
        .s1_bready  (dma_reg_bready),
        .s1_araddr  (dma_reg_araddr),
        .s1_arvalid (dma_reg_arvalid),
        .s1_arready (dma_reg_arready),
        .s1_rdata   (dma_reg_rdata),
        .s1_rresp   (dma_reg_rresp),
        .s1_rvalid  (dma_reg_rvalid),
        .s1_rready  (dma_reg_rready),

        // slave 2
        .s2_awaddr  (periph_awaddr),
        .s2_awvalid (periph_awvalid),
        .s2_awready (periph_awready),
        .s2_wdata   (periph_wdata),
        .s2_wstrb   (periph_wstrb),
        .s2_wvalid  (periph_wvalid),
        .s2_wready  (periph_wready),
        .s2_bresp   (periph_bresp),
        .s2_bvalid  (periph_bvalid),
        .s2_bready  (periph_bready),
        .s2_araddr  (periph_araddr),
        .s2_arvalid (periph_arvalid),
        .s2_arready (periph_arready),
        .s2_rdata   (periph_rdata),
        .s2_rresp   (periph_rresp),
        .s2_rvalid  (periph_rvalid),
        .s2_rready  (periph_rready),

        // slave 3
        .s3_awaddr  (imem_awaddr),
        .s3_awvalid (imem_awvalid),
        .s3_awready (imem_awready),
        .s3_wdata   (imem_wdata),
        .s3_wstrb   (imem_wstrb),
        .s3_wvalid  (imem_wvalid),
        .s3_wready  (imem_wready),
        .s3_bresp   (imem_bresp),
        .s3_bvalid  (imem_bvalid),
        .s3_bready  (imem_bready),
        .s3_araddr  (imem_araddr),
        .s3_arvalid (imem_arvalid),
        .s3_arready (imem_arready),
        .s3_rdata   (imem_rdata),
        .s3_rresp   (imem_rresp),
        .s3_rvalid  (imem_rvalid),
        .s3_rready  (imem_rready)
    );

endmodule
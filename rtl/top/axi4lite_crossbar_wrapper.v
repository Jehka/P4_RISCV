// axi4lite_crossbar_wrapper.v  (3 masters x 4 slaves)
//
// Plain-Verilog IPI wrapper around axi4lite_crossbar. The SV module uses
// packed-array ports (m_awaddr[NUM_MASTERS-1:0][...]), which IP Integrator
// cannot infer as separate AXI interfaces, so this file flattens each
// array element into an individually-named signal. Same fix pattern as
// minerva_p2p3_wrapper.v uses for the CPU.
//
// Connections use plain Verilog concatenation directly in the
// instantiation -- legal for both input and output ports, and
// bit-width-matched against the SV module's packed dimensions. No SV
// syntax appears in this file.
//
// Concatenation order: {m2,m1,m0} places m0 at array index 0, matching
// axi4lite_crossbar's indexing. Same for {s3,s2,s1,s0}.
//
// REGENERATE this file if NUM_MASTERS or NUM_SLAVES changes -- it is not
// parameterisable, because IPI needs a fixed flat port list.
//
//   master 0: riscv_cpu_p4's ext_mem  (CPU data: cache + DMA via p3_top)
//   master 1: fault_injection_master's m_axi (P5 fault campaigns)
//   master 2: riscv_cpu_p4's instr_mem (AXI instruction fetch)
//   slave  0: data mem     0x0000_0000-0x0000_3FFF  (to AXI BRAM Controller)
//   slave  1: dma_reg      0x0001_0000-0x0001_00FF  (loops back into the CPU)
//   slave  2: periph       0x0002_0000-0x0002_00FF  (reserved; MUST be tied off)
//   slave  3: imem         0x0003_0000-0x0003_0FFF  (to AXI BRAM Controller)

module axi4lite_crossbar_wrapper (
    input  wire clk,
    input  wire rst_n,

    // ---- Master 0: riscv_cpu_p4's ext_mem  (CPU data: cache + DMA via p3_top) ----
    input  wire [31:0] m0_awaddr,
    input  wire m0_awvalid,
    output wire m0_awready,
    input  wire [31:0] m0_wdata,
    input  wire [3:0] m0_wstrb,
    input  wire m0_wvalid,
    output wire m0_wready,
    output wire [1:0] m0_bresp,
    output wire m0_bvalid,
    input  wire m0_bready,
    input  wire [31:0] m0_araddr,
    input  wire m0_arvalid,
    output wire m0_arready,
    output wire [31:0] m0_rdata,
    output wire [1:0] m0_rresp,
    output wire m0_rvalid,
    input  wire m0_rready,

    // ---- Master 1: fault_injection_master's m_axi (P5 fault campaigns) ----
    input  wire [31:0] m1_awaddr,
    input  wire m1_awvalid,
    output wire m1_awready,
    input  wire [31:0] m1_wdata,
    input  wire [3:0] m1_wstrb,
    input  wire m1_wvalid,
    output wire m1_wready,
    output wire [1:0] m1_bresp,
    output wire m1_bvalid,
    input  wire m1_bready,
    input  wire [31:0] m1_araddr,
    input  wire m1_arvalid,
    output wire m1_arready,
    output wire [31:0] m1_rdata,
    output wire [1:0] m1_rresp,
    output wire m1_rvalid,
    input  wire m1_rready,

    // ---- Master 2: riscv_cpu_p4's instr_mem (AXI instruction fetch) ----
    input  wire [31:0] m2_awaddr,
    input  wire m2_awvalid,
    output wire m2_awready,
    input  wire [31:0] m2_wdata,
    input  wire [3:0] m2_wstrb,
    input  wire m2_wvalid,
    output wire m2_wready,
    output wire [1:0] m2_bresp,
    output wire m2_bvalid,
    input  wire m2_bready,
    input  wire [31:0] m2_araddr,
    input  wire m2_arvalid,
    output wire m2_arready,
    output wire [31:0] m2_rdata,
    output wire [1:0] m2_rresp,
    output wire m2_rvalid,
    input  wire m2_rready,

    // ---- Slave 0: data mem     0x0000_0000-0x0000_3FFF  (to AXI BRAM Controller) ----
    output wire [31:0] s0_awaddr,
    output wire s0_awvalid,
    input  wire s0_awready,
    output wire [31:0] s0_wdata,
    output wire [3:0] s0_wstrb,
    output wire s0_wvalid,
    input  wire s0_wready,
    input  wire [1:0] s0_bresp,
    input  wire s0_bvalid,
    output wire s0_bready,
    output wire [31:0] s0_araddr,
    output wire s0_arvalid,
    input  wire s0_arready,
    input  wire [31:0] s0_rdata,
    input  wire [1:0] s0_rresp,
    input  wire s0_rvalid,
    output wire s0_rready,

    // ---- Slave 1: dma_reg      0x0001_0000-0x0001_00FF  (loops back into the CPU) ----
    output wire [31:0] s1_awaddr,
    output wire s1_awvalid,
    input  wire s1_awready,
    output wire [31:0] s1_wdata,
    output wire [3:0] s1_wstrb,
    output wire s1_wvalid,
    input  wire s1_wready,
    input  wire [1:0] s1_bresp,
    input  wire s1_bvalid,
    output wire s1_bready,
    output wire [31:0] s1_araddr,
    output wire s1_arvalid,
    input  wire s1_arready,
    input  wire [31:0] s1_rdata,
    input  wire [1:0] s1_rresp,
    input  wire s1_rvalid,
    output wire s1_rready,

    // ---- Slave 2: periph       0x0002_0000-0x0002_00FF  (reserved; MUST be tied off) ----
    output wire [31:0] s2_awaddr,
    output wire s2_awvalid,
    input  wire s2_awready,
    output wire [31:0] s2_wdata,
    output wire [3:0] s2_wstrb,
    output wire s2_wvalid,
    input  wire s2_wready,
    input  wire [1:0] s2_bresp,
    input  wire s2_bvalid,
    output wire s2_bready,
    output wire [31:0] s2_araddr,
    output wire s2_arvalid,
    input  wire s2_arready,
    input  wire [31:0] s2_rdata,
    input  wire [1:0] s2_rresp,
    input  wire s2_rvalid,
    output wire s2_rready,

    // ---- Slave 3: imem         0x0003_0000-0x0003_0FFF  (to AXI BRAM Controller) ----
    output wire [31:0] s3_awaddr,
    output wire s3_awvalid,
    input  wire s3_awready,
    output wire [31:0] s3_wdata,
    output wire [3:0] s3_wstrb,
    output wire s3_wvalid,
    input  wire s3_wready,
    input  wire [1:0] s3_bresp,
    input  wire s3_bvalid,
    output wire s3_bready,
    output wire [31:0] s3_araddr,
    output wire s3_arvalid,
    input  wire s3_arready,
    input  wire [31:0] s3_rdata,
    input  wire [1:0] s3_rresp,
    input  wire s3_rvalid,
    output wire s3_rready
);

    axi4lite_crossbar #(
        .NUM_MASTERS(3),
        .NUM_SLAVES (4)
        // SLAVE_BASE/SLAVE_HIGH left at module defaults
    ) u_crossbar (
        .clk   (clk),
        .rst_n (rst_n),

        .m_awaddr  ({m2_awaddr, m1_awaddr, m0_awaddr}),
        .m_awvalid ({m2_awvalid, m1_awvalid, m0_awvalid}),
        .m_awready ({m2_awready, m1_awready, m0_awready}),
        .m_wdata   ({m2_wdata, m1_wdata, m0_wdata}),
        .m_wstrb   ({m2_wstrb, m1_wstrb, m0_wstrb}),
        .m_wvalid  ({m2_wvalid, m1_wvalid, m0_wvalid}),
        .m_wready  ({m2_wready, m1_wready, m0_wready}),
        .m_bresp   ({m2_bresp, m1_bresp, m0_bresp}),
        .m_bvalid  ({m2_bvalid, m1_bvalid, m0_bvalid}),
        .m_bready  ({m2_bready, m1_bready, m0_bready}),
        .m_araddr  ({m2_araddr, m1_araddr, m0_araddr}),
        .m_arvalid ({m2_arvalid, m1_arvalid, m0_arvalid}),
        .m_arready ({m2_arready, m1_arready, m0_arready}),
        .m_rdata   ({m2_rdata, m1_rdata, m0_rdata}),
        .m_rresp   ({m2_rresp, m1_rresp, m0_rresp}),
        .m_rvalid  ({m2_rvalid, m1_rvalid, m0_rvalid}),
        .m_rready  ({m2_rready, m1_rready, m0_rready}),

        .s_awaddr  ({s3_awaddr, s2_awaddr, s1_awaddr, s0_awaddr}),
        .s_awvalid ({s3_awvalid, s2_awvalid, s1_awvalid, s0_awvalid}),
        .s_awready ({s3_awready, s2_awready, s1_awready, s0_awready}),
        .s_wdata   ({s3_wdata, s2_wdata, s1_wdata, s0_wdata}),
        .s_wstrb   ({s3_wstrb, s2_wstrb, s1_wstrb, s0_wstrb}),
        .s_wvalid  ({s3_wvalid, s2_wvalid, s1_wvalid, s0_wvalid}),
        .s_wready  ({s3_wready, s2_wready, s1_wready, s0_wready}),
        .s_bresp   ({s3_bresp, s2_bresp, s1_bresp, s0_bresp}),
        .s_bvalid  ({s3_bvalid, s2_bvalid, s1_bvalid, s0_bvalid}),
        .s_bready  ({s3_bready, s2_bready, s1_bready, s0_bready}),
        .s_araddr  ({s3_araddr, s2_araddr, s1_araddr, s0_araddr}),
        .s_arvalid ({s3_arvalid, s2_arvalid, s1_arvalid, s0_arvalid}),
        .s_arready ({s3_arready, s2_arready, s1_arready, s0_arready}),
        .s_rdata   ({s3_rdata, s2_rdata, s1_rdata, s0_rdata}),
        .s_rresp   ({s3_rresp, s2_rresp, s1_rresp, s0_rresp}),
        .s_rvalid  ({s3_rvalid, s2_rvalid, s1_rvalid, s0_rvalid}),
        .s_rready  ({s3_rready, s2_rready, s1_rready, s0_rready})
    );

endmodule
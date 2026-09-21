// axi4lite_ports.vh
// Flattened AXI4-Lite MASTER port list, included via `include in modules that
// act as an AXI4-Lite master (cache_controller, dma_engine).
// Flattened (not SV interface) because Vivado IP Integrator cannot infer
// SystemVerilog interfaces -- same workaround used in P1 (rr_arbiter/cdc_arbiter).
//
// Usage:
//   module cache_controller (
//     input  logic clk, rst_n,
//     `AXI4LITE_MASTER_PORTS(m_axi)
//     ... other ports
//   );

`define AXI4LITE_MASTER_PORTS(PFX) \
    output logic [31:0]            PFX``_awaddr,  \
    output logic                   PFX``_awvalid, \
    input  logic                   PFX``_awready, \
    output logic [31:0]            PFX``_wdata,   \
    output logic [3:0]             PFX``_wstrb,   \
    output logic                   PFX``_wvalid,  \
    input  logic                   PFX``_wready,  \
    input  logic [1:0]             PFX``_bresp,   \
    input  logic                   PFX``_bvalid,  \
    output logic                   PFX``_bready,  \
    output logic [31:0]            PFX``_araddr,  \
    output logic                   PFX``_arvalid, \
    input  logic                   PFX``_arready, \
    input  logic [31:0]            PFX``_rdata,   \
    input  logic [1:0]             PFX``_rresp,   \
    input  logic                   PFX``_rvalid,  \
    output logic                   PFX``_rready

`define AXI4LITE_SLAVE_PORTS(PFX) \
    input  logic [31:0]            PFX``_awaddr,  \
    input  logic                   PFX``_awvalid, \
    output logic                   PFX``_awready, \
    input  logic [31:0]            PFX``_wdata,   \
    input  logic [3:0]             PFX``_wstrb,   \
    input  logic                   PFX``_wvalid,  \
    output logic                   PFX``_wready,  \
    output logic [1:0]             PFX``_bresp,   \
    output logic                   PFX``_bvalid,  \
    input  logic                   PFX``_bready,  \
    input  logic [31:0]            PFX``_araddr,  \
    input  logic                   PFX``_arvalid, \
    output logic                   PFX``_arready, \
    output logic [31:0]            PFX``_rdata,   \
    output logic [1:0]             PFX``_rresp,   \
    output logic                   PFX``_rvalid,  \
    input  logic                   PFX``_rready

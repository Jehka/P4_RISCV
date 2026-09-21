// axi4lite_pkg.sv
// Common AXI4-Lite parameters for MINERVA P3-P5.
// Single source of truth so cache, DMA, and crossbar (P4) stay interface-compatible.

package axi4lite_pkg;

  parameter int AXI_ADDR_WIDTH = 32;
  parameter int AXI_DATA_WIDTH = 32;
  parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH/8;

  // AXI4-Lite RESP encoding
  typedef enum logic [1:0] {
    RESP_OKAY   = 2'b00,
    RESP_EXOKAY = 2'b01, // unused in Lite, reserved
    RESP_SLVERR = 2'b10,
    RESP_DECERR = 2'b11
  } axi_resp_e;

endpackage : axi4lite_pkg
// axi4lite_mem_model.sv
// Behavioral AXI4-Lite slave memory for simulation only. Not synthesizable
// intent -- just enough handshake fidelity to exercise p3_top in sim.

`include "axi4lite_ports.vh"

module axi4lite_mem_model #(
    parameter int MEM_WORDS = 4096
) (
    input logic clk,
    input logic rst_n,
    `AXI4LITE_SLAVE_PORTS(s_axi)
);

  logic [31:0] mem [MEM_WORDS];

  typedef enum logic [1:0] {IDLE, BRESP, RRESP} state_e;
  state_e state_q;

  logic [31:0] awaddr_q, araddr_q;
  logic [31:0] bvalid_q_data;

  logic bvalid_q, rvalid_q;
  logic [31:0] rdata_q;
  int wr_idx, rd_idx;

  assign s_axi_awready = (state_q == IDLE);
  assign s_axi_wready  = (state_q == IDLE);
  assign s_axi_arready = (state_q == IDLE);
  assign s_axi_bresp   = 2'b00;
  assign s_axi_rresp   = 2'b00;
  assign s_axi_bvalid  = bvalid_q;
  assign s_axi_rvalid  = rvalid_q;
  assign s_axi_rdata   = rdata_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q  <= IDLE;
      bvalid_q <= 1'b0;
      rvalid_q <= 1'b0;
    end else begin
      if (bvalid_q && s_axi_bready) bvalid_q <= 1'b0;
      if (rvalid_q && s_axi_rready) rvalid_q <= 1'b0;

      unique case (state_q)
        IDLE: begin
          if (s_axi_awvalid && s_axi_wvalid) begin
            wr_idx = s_axi_awaddr[31:2] % MEM_WORDS;
            for (int b = 0; b < 4; b++)
              if (s_axi_wstrb[b]) mem[wr_idx][b*8 +: 8] <= s_axi_wdata[b*8 +: 8];
            bvalid_q <= 1'b1;
          end else if (s_axi_arvalid) begin
            rd_idx = s_axi_araddr[31:2] % MEM_WORDS;
            rdata_q  <= mem[rd_idx];
            rvalid_q <= 1'b1;
          end
        end
        default: ;
      endcase
    end
  end

endmodule : axi4lite_mem_model
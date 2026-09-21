// mem_stage_axi.sv
// MINERVA P2+P3 integration - replaces the old zero-latency mem_stage.sv.
// Translates P2's byte/halfword/word load-store fields into the word-plus-
// byte-enable request that cache_controller's CPU-side port expects, and
// asserts mem_stall for every cycle a cache access is outstanding (cache
// hits still take 1 cycle here; misses take the cache's multi-cycle
// allocate/writeback path).

module mem_stage_axi (
    input  logic        clk,
    input  logic        rst_n,

    input  logic         mem_read,
    input  logic         mem_write,
    input  logic [2:0]   funct3,
    input  logic [31:0]  alu_result,   // memory address
    input  logic [31:0]  rs2_data,     // store data (untransformed)

    output logic [31:0]  mem_data,     // load data out (sign/zero extended)
    output logic         mem_stall,    // 1 = freeze the whole pipeline

    // cache_controller CPU-side port
    output logic         cpu_req_valid,
    input  logic         cpu_req_ready,
    output logic [31:0]  cpu_req_addr,
    output logic [31:0]  cpu_req_wdata,
    output logic [3:0]   cpu_req_be,
    output logic         cpu_req_we,
    input  logic         cpu_resp_valid,
    input  logic [31:0]  cpu_resp_rdata
);

  // ---------------- store data / byte-enable shaping ----------------
  // Cache is word-addressed with byte-enables; P2 gives us alu_result's
  // low 2 bits for byte/halfword position within the word.
  logic [31:0] store_wdata;
  logic [3:0]  store_be;

  always_comb begin
    store_wdata = rs2_data;
    store_be    = 4'h0;
    unique case (funct3)
      3'b000: begin // SB
        unique case (alu_result[1:0])
          2'b00: begin store_wdata = {24'b0, rs2_data[7:0]};         store_be = 4'b0001; end
          2'b01: begin store_wdata = {16'b0, rs2_data[7:0], 8'b0};   store_be = 4'b0010; end
          2'b10: begin store_wdata = {8'b0, rs2_data[7:0], 16'b0};   store_be = 4'b0100; end
          2'b11: begin store_wdata = {rs2_data[7:0], 24'b0};         store_be = 4'b1000; end
        endcase
      end
      3'b001: begin // SH
        unique case (alu_result[1])
          1'b0: begin store_wdata = {16'b0, rs2_data[15:0]};  store_be = 4'b0011; end
          1'b1: begin store_wdata = {rs2_data[15:0], 16'b0};  store_be = 4'b1100; end
        endcase
      end
      default: begin // SW
        store_wdata = rs2_data;
        store_be    = 4'b1111;
      end
    endcase
  end

  // ---------------- request FSM ----------------
  typedef enum logic [1:0] {M_IDLE, M_REQ, M_WAIT} mstate_e;
  mstate_e state_q;

  logic [31:0] resp_rdata_q;

  assign cpu_req_addr  = alu_result;
  assign cpu_req_wdata = store_wdata;
  assign cpu_req_be    = mem_write ? store_be : 4'hF;
  assign cpu_req_we    = mem_write;
  assign cpu_req_valid = (state_q == M_REQ);

  // mem_stall high any cycle we have a pending op not yet resolved
  assign mem_stall = (mem_read | mem_write) &&
                      !((state_q == M_IDLE) ? 1'b0 :
                        (state_q == M_WAIT) ? cpu_resp_valid : 1'b0);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q      <= M_IDLE;
      resp_rdata_q <= '0;
    end else begin
      unique case (state_q)
        M_IDLE: begin
          if (mem_read || mem_write) state_q <= M_REQ;
        end
        M_REQ: begin
          if (cpu_req_ready) state_q <= M_WAIT;
        end
        M_WAIT: begin
          if (cpu_resp_valid) begin
            resp_rdata_q <= cpu_resp_rdata;
            state_q      <= M_IDLE;
          end
        end
        default: state_q <= M_IDLE;
      endcase
    end
  end

  // ---------------- load sign/zero extension ----------------
  logic [31:0] raw_word;
  assign raw_word = cpu_resp_valid ? cpu_resp_rdata : resp_rdata_q;

  always_comb begin
    mem_data = 32'b0;
    if (mem_read) begin
      unique case (funct3)
        3'b000: begin // LB
          unique case (alu_result[1:0])
            2'b00: mem_data = {{24{raw_word[7]}},  raw_word[7:0]};
            2'b01: mem_data = {{24{raw_word[15]}}, raw_word[15:8]};
            2'b10: mem_data = {{24{raw_word[23]}}, raw_word[23:16]};
            2'b11: mem_data = {{24{raw_word[31]}}, raw_word[31:24]};
          endcase
        end
        3'b001: begin // LH
          unique case (alu_result[1])
            1'b0: mem_data = {{16{raw_word[15]}}, raw_word[15:0]};
            1'b1: mem_data = {{16{raw_word[31]}}, raw_word[31:16]};
          endcase
        end
        3'b010: mem_data = raw_word; // LW
        3'b100: begin // LBU
          unique case (alu_result[1:0])
            2'b00: mem_data = {24'b0, raw_word[7:0]};
            2'b01: mem_data = {24'b0, raw_word[15:8]};
            2'b10: mem_data = {24'b0, raw_word[23:16]};
            2'b11: mem_data = {24'b0, raw_word[31:24]};
          endcase
        end
        3'b101: begin // LHU
          unique case (alu_result[1])
            1'b0: mem_data = {16'b0, raw_word[15:0]};
            1'b1: mem_data = {16'b0, raw_word[31:16]};
          endcase
        end
        default: mem_data = raw_word;
      endcase
    end
  end

endmodule : mem_stage_axi
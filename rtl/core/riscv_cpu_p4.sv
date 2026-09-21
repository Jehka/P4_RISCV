// riscv_cpu_p4.sv - MINERVA P4 integration top level
//
// Derived from riscv_cpu_p3.sv. riscv_cpu_p3.sv is left UNTOUCHED so the
// hardware-verified P3 configuration stays available.
//
// ONE functional change: instruction fetch now goes over AXI4-Lite
// (if_stage_axi) instead of if_stage's internal ROM, so programs are
// runtime-loadable and instruction memory is reachable by the
// fault-injection master.
//
// NOTE ON THE PIPELINE ENABLES -- deliberately NOT changed:
// It is tempting to fold if_stall into pc_en/if_id_en/... alongside
// mem_stall. That is WRONG and livelocks. Freezing EX/MEM holds
// ex_mem_branch_taken asserted; once the redirect fetch completed,
// if_stage_axi would see the redirect again and re-redirect to the same
// target forever. Instead:
//   - if_stage_axi drives instr = NOP while a fetch is outstanding, so
//     IF/ID captures bubbles and the back-end drains by itself;
//   - it holds in IF_VALID while pc_write is low, so a cache stall holds
//     the fetched instruction exactly as the old combinational fetch did;
//   - EX/MEM keeps advancing, so ex_mem_branch_taken stays a genuine
//     one-cycle pulse -- which is what if_stage_axi's redirect latch
//     exists to capture.
// Same 5-stage pipeline as riscv_cpu.sv, but MEM stage now goes through
// mem_stage_axi -> cache_controller (p3_top's cache side) instead of a
// zero-latency local array. A cache access can take 1 cycle (hit) to
// ~9+ cycles (miss with writeback+allocate); mem_stall freezes PC, IF/ID,
// ID/EX, and EX/MEM for the duration, and holds MEM/WB until the result
// is ready.
//
// DMA register port and DMA IRQ are exposed at top level for the CPU (or
// eventually an interrupt controller) to program transfers independently
// of the cache path.

`include "axi4lite_ports.vh"

module riscv_cpu_p4 #(
    // Instruction memory base on the crossbar (slave 3). Must match the
    // crossbar's SLAVE_BASE[3] or fetches will decode to the wrong slave.
    parameter logic [31:0] IMEM_BASE = 32'h0003_0000
)(
    input  logic        clk, rst,
    output logic [31:0] debug_out,
    output logic         mem_stall_out,
    output logic [31:0]  if_pc_out,

    // DMA programming port (CPU or external agent can drive this)
    `AXI4LITE_SLAVE_PORTS(dma_reg),
    output logic         dma_irq,

    // Shared external DATA memory (AXI4-Lite master -> crossbar master 0)
    `AXI4LITE_MASTER_PORTS(ext_mem),

    // NEW in P4: instruction fetch is its own AXI4-Lite master
    // (-> crossbar master 2, targeting imem at slave 3). Kept separate
    // from ext_mem deliberately: routing it through cache_dma_arbiter
    // would mean editing P3's hardware-verified 2-way arbiter, whereas
    // the crossbar already generalises exactly this.
    `AXI4LITE_MASTER_PORTS(instr_mem),

    output logic         if_stall_out
);

    // ══ IF/ID pipeline register ═══════════════════════════════════
    logic [31:0] if_id_pc, if_id_pc_plus4, if_id_instr;

    // ══ ID/EX pipeline register ═══════════════════════════════════
    logic [31:0] id_ex_pc, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic [2:0]  id_ex_funct3;
    logic        id_ex_funct7_5;
    logic [6:0]  id_ex_opcode;
    logic        id_ex_reg_write, id_ex_mem_to_reg;
    logic        id_ex_mem_read,  id_ex_mem_write;
    logic        id_ex_branch,    id_ex_jump;
    logic        id_ex_alu_src;
    logic [1:0]  id_ex_alu_op;

    // ══ EX/MEM pipeline register ══════════════════════════════════
    logic [31:0] ex_mem_alu_result, ex_mem_rs2_data;
    logic [4:0]  ex_mem_rd;
    logic        ex_mem_reg_write, ex_mem_mem_to_reg;
    logic        ex_mem_mem_read,  ex_mem_mem_write;
    logic [2:0]  ex_mem_funct3;
    logic        ex_mem_branch_taken;
    logic [31:0] ex_mem_branch_target;

    // ══ MEM/WB pipeline register ══════════════════════════════════
    logic [31:0] mem_wb_alu_result, mem_wb_mem_data;
    logic [4:0]  mem_wb_rd;
    logic        mem_wb_reg_write, mem_wb_mem_to_reg;

    // ══ hazard and forwarding signals ═════════════════════════════
    logic        pc_write, if_id_write;
    logic        id_ex_flush, if_id_flush;
    logic [1:0]  forwardA, forwardB;
    logic        mem_stall;               // NEW: cache multi-cycle stall

    // ══ stage outputs ═════════════════════════════════════════════
    logic [31:0] if_instr, if_pc, if_pc_plus4;
    logic [31:0] id_rd1, id_rd2, id_imm;
    logic [4:0]  id_rs1, id_rs2, id_rd;
    logic        id_reg_write, id_mem_to_reg;
    logic        id_mem_read,  id_mem_write;
    logic        id_branch,    id_jump, id_alu_src;
    logic [1:0]  id_alu_op;
    logic [31:0] ex_alu_result, ex_rs2_out;
    logic        ex_branch_taken;
    logic [31:0] ex_branch_target;
    logic [31:0] mem_mem_data;
    logic [31:0] wb_data;

    // effective enables: existing hazards AND not stalled on a cache access
    wire pc_en     = pc_write    & ~mem_stall;
    wire if_id_en  = if_id_write & ~mem_stall;
    wire id_ex_en  = ~mem_stall;
    wire ex_mem_en = ~mem_stall;
    wire mem_wb_en = ~mem_stall;

    // ══ IF stage ══════════════════════════════════════════════════
    logic if_stall;

    if_stage_axi #(.IMEM_BASE(IMEM_BASE)) u_if (
        .clk            (clk),
        .rst            (rst),
        .pc_write       (pc_en),
        .pc_sel         (ex_mem_branch_taken),
        .branch_target  (ex_mem_branch_target),
        .instr          (if_instr),
        .pc             (if_pc),
        .pc_plus4       (if_pc_plus4),
        .if_stall       (if_stall),
        .i_axi_awaddr (instr_mem_awaddr),  .i_axi_awvalid(instr_mem_awvalid), .i_axi_awready(instr_mem_awready),
        .i_axi_wdata  (instr_mem_wdata),   .i_axi_wstrb  (instr_mem_wstrb),   .i_axi_wvalid (instr_mem_wvalid), .i_axi_wready(instr_mem_wready),
        .i_axi_bresp  (instr_mem_bresp),   .i_axi_bvalid (instr_mem_bvalid),  .i_axi_bready (instr_mem_bready),
        .i_axi_araddr (instr_mem_araddr),  .i_axi_arvalid(instr_mem_arvalid), .i_axi_arready(instr_mem_arready),
        .i_axi_rdata  (instr_mem_rdata),   .i_axi_rresp  (instr_mem_rresp),   .i_axi_rvalid (instr_mem_rvalid), .i_axi_rready(instr_mem_rready)
    );

    // ══ IF/ID register ════════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst || (if_id_flush && !mem_stall)) begin
            if_id_instr    <= 32'h0000_0013; // NOP = ADDI x0,x0,0
            if_id_pc       <= 32'b0;
            if_id_pc_plus4 <= 32'b0;
        end else if (if_id_en) begin
            if_id_instr    <= if_instr;
            if_id_pc       <= if_pc;
            if_id_pc_plus4 <= if_pc_plus4;
        end
        // if_id_en=0 and no flush → hold value (stall)
    end

    // ══ ID stage ══════════════════════════════════════════════════
    // x10 / a0 brought out of the regfile through a real port.
    logic [31:0] dbg_x10_w;

    id_stage u_id (
        .clk            (clk),
        .rst            (rst),
        .instr          (if_id_instr),
        .pc             (if_id_pc),
        .reg_write_wb   (mem_wb_reg_write),
        .rd_wb          (mem_wb_rd),
        .wd_wb          (wb_data),
        .reg_write      (id_reg_write),
        .mem_to_reg     (id_mem_to_reg),
        .mem_read       (id_mem_read),
        .mem_write      (id_mem_write),
        .branch         (id_branch),
        .alu_src        (id_alu_src),
        .alu_op         (id_alu_op),
        .jump           (id_jump),
        .rd1            (id_rd1),
        .rd2            (id_rd2),
        .imm            (id_imm),
        .rs1            (id_rs1),
        .rs2            (id_rs2),
        .rd             (id_rd),
        .dbg_x10       (dbg_x10_w)
    );

    // ══ ID/EX register ════════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst || (id_ex_flush && !mem_stall)) begin
            id_ex_pc         <= 32'b0;
            id_ex_rs1_data   <= 32'b0;
            id_ex_rs2_data   <= 32'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rs1        <= 5'b0;
            id_ex_rs2        <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_funct3     <= 3'b0;
            id_ex_funct7_5   <= 1'b0;
            id_ex_opcode     <= 7'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_to_reg <= 1'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
            id_ex_branch     <= 1'b0;
            id_ex_jump       <= 1'b0;
            id_ex_alu_src    <= 1'b0;
            id_ex_alu_op     <= 2'b0;
        end else if (id_ex_en) begin
            id_ex_pc         <= if_id_pc;
            id_ex_rs1_data   <= id_rd1;
            id_ex_rs2_data   <= id_rd2;
            id_ex_imm        <= id_imm;
            id_ex_rs1        <= id_rs1;
            id_ex_rs2        <= id_rs2;
            id_ex_rd         <= id_rd;
            id_ex_funct3     <= if_id_instr[14:12];
            id_ex_funct7_5   <= if_id_instr[30];
            id_ex_opcode     <= if_id_instr[6:0];
            id_ex_reg_write  <= id_reg_write;
            id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_mem_read   <= id_mem_read;
            id_ex_mem_write  <= id_mem_write;
            id_ex_branch     <= id_branch;
            id_ex_jump       <= id_jump;
            id_ex_alu_src    <= id_alu_src;
            id_ex_alu_op     <= id_alu_op;
        end
        // id_ex_en=0 (mem_stall, no flush) → hold value
    end

    // ══ EX stage ══════════════════════════════════════════════════
    ex_stage u_ex (
        .pc             (id_ex_pc),
        .rs1_data       (id_ex_rs1_data),
        .rs2_data       (id_ex_rs2_data),
        .imm            (id_ex_imm),
        .rs1            (id_ex_rs1),
        .rs2            (id_ex_rs2),
        .rd             (id_ex_rd),
        .alu_src        (id_ex_alu_src),
        .alu_op         (id_ex_alu_op),
        .branch         (id_ex_branch),
        .jump           (id_ex_jump),
        .funct3         (id_ex_funct3),
        .funct7_5       (id_ex_funct7_5),
        .opcode         (id_ex_opcode),
        .forwardA       (forwardA),
        .forwardB       (forwardB),
        .ex_mem_result  (ex_mem_alu_result),
        .mem_wb_data    (wb_data),
        .alu_result     (ex_alu_result),
        .rs2_out        (ex_rs2_out),
        .branch_taken   (ex_branch_taken),
        .branch_target  (ex_branch_target)
    );

    // ══ EX/MEM register ═══════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            ex_mem_alu_result    <= 32'b0;
            ex_mem_rs2_data      <= 32'b0;
            ex_mem_rd            <= 5'b0;
            ex_mem_reg_write     <= 1'b0;
            ex_mem_mem_to_reg    <= 1'b0;
            ex_mem_mem_read      <= 1'b0;
            ex_mem_mem_write     <= 1'b0;
            ex_mem_funct3        <= 3'b0;
            ex_mem_branch_taken  <= 1'b0;
            ex_mem_branch_target <= 32'b0;
        end else if (ex_mem_en) begin
            ex_mem_alu_result    <= ex_alu_result;
            ex_mem_rs2_data      <= ex_rs2_out;
            ex_mem_rd            <= id_ex_rd;
            ex_mem_reg_write     <= id_ex_reg_write;
            ex_mem_mem_to_reg    <= id_ex_mem_to_reg;
            ex_mem_mem_read      <= id_ex_mem_read;
            ex_mem_mem_write     <= id_ex_mem_write;
            ex_mem_funct3        <= id_ex_funct3;
            ex_mem_branch_taken  <= ex_branch_taken;
            ex_mem_branch_target <= ex_branch_target;
        end
        // ex_mem_en=0 (mem_stall) → hold: keeps driving the in-flight
        // cache request's address/data steady until it completes
    end

    // ══ MEM stage: adapter + cache ═══════════════════════════════
    logic         cpu_req_valid, cpu_req_ready, cpu_req_we;
    logic [31:0]  cpu_req_addr, cpu_req_wdata;
    logic [3:0]   cpu_req_be;
    logic         cpu_resp_valid;
    logic [31:0]  cpu_resp_rdata;

    mem_stage_axi u_mem_adapter (
        .clk        (clk),
        .rst_n      (~rst),
        .mem_read   (ex_mem_mem_read),
        .mem_write  (ex_mem_mem_write),
        .funct3     (ex_mem_funct3),
        .alu_result (ex_mem_alu_result),
        .rs2_data   (ex_mem_rs2_data),
        .mem_data   (mem_mem_data),
        .mem_stall  (mem_stall),
        .cpu_req_valid (cpu_req_valid),
        .cpu_req_ready (cpu_req_ready),
        .cpu_req_addr  (cpu_req_addr),
        .cpu_req_wdata (cpu_req_wdata),
        .cpu_req_be    (cpu_req_be),
        .cpu_req_we    (cpu_req_we),
        .cpu_resp_valid(cpu_resp_valid),
        .cpu_resp_rdata(cpu_resp_rdata)
    );

    p3_top u_p3 (
        .clk (clk), .rst_n (~rst),
        .cpu_req_valid (cpu_req_valid), .cpu_req_ready (cpu_req_ready),
        .cpu_req_addr  (cpu_req_addr),  .cpu_req_wdata (cpu_req_wdata),
        .cpu_req_be    (cpu_req_be),    .cpu_req_we    (cpu_req_we),
        .cpu_resp_valid(cpu_resp_valid),.cpu_resp_rdata(cpu_resp_rdata),
        .dma_reg_awaddr(dma_reg_awaddr), .dma_reg_awvalid(dma_reg_awvalid), .dma_reg_awready(dma_reg_awready),
        .dma_reg_wdata (dma_reg_wdata),  .dma_reg_wstrb  (dma_reg_wstrb),   .dma_reg_wvalid (dma_reg_wvalid), .dma_reg_wready(dma_reg_wready),
        .dma_reg_bresp (dma_reg_bresp),  .dma_reg_bvalid (dma_reg_bvalid),  .dma_reg_bready (dma_reg_bready),
        .dma_reg_araddr(dma_reg_araddr), .dma_reg_arvalid(dma_reg_arvalid), .dma_reg_arready(dma_reg_arready),
        .dma_reg_rdata (dma_reg_rdata),  .dma_reg_rresp  (dma_reg_rresp),   .dma_reg_rvalid (dma_reg_rvalid), .dma_reg_rready(dma_reg_rready),
        .dma_irq (dma_irq),
        .mem_awaddr(ext_mem_awaddr), .mem_awvalid(ext_mem_awvalid), .mem_awready(ext_mem_awready),
        .mem_wdata (ext_mem_wdata),  .mem_wstrb  (ext_mem_wstrb),   .mem_wvalid (ext_mem_wvalid), .mem_wready(ext_mem_wready),
        .mem_bresp (ext_mem_bresp),  .mem_bvalid (ext_mem_bvalid),  .mem_bready (ext_mem_bready),
        .mem_araddr(ext_mem_araddr), .mem_arvalid(ext_mem_arvalid), .mem_arready(ext_mem_arready),
        .mem_rdata (ext_mem_rdata),  .mem_rresp  (ext_mem_rresp),   .mem_rvalid (ext_mem_rvalid), .mem_rready(ext_mem_rready)
    );

    // ══ MEM/WB register ═══════════════════════════════════════════
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            mem_wb_alu_result <= 32'b0;
            mem_wb_mem_data   <= 32'b0;
            mem_wb_rd         <= 5'b0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 1'b0;
        end else if (mem_wb_en) begin
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_data   <= mem_mem_data;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
        end
        // mem_wb_en=0 (mem_stall) → hold: WB doesn't advance until the
        // cache access actually completes and mem_mem_data is valid
    end

    // ══ WB stage ══════════════════════════════════════════════════
    wb_stage u_wb (
        .mem_to_reg (mem_wb_mem_to_reg),
        .alu_result (mem_wb_alu_result),
        .mem_data   (mem_wb_mem_data),
        .wb_data    (wb_data)
    );

    // ══ hazard unit ═══════════════════════════════════════════════
    hazard_unit u_hazard (
        .id_ex_mem_read (id_ex_mem_read),
        .id_ex_rd       (id_ex_rd),
        .if_id_rs1      (if_id_instr[19:15]),
        .if_id_rs2      (if_id_instr[24:20]),
        .ex_branch_taken(ex_branch_taken),
        .branch_taken   (ex_mem_branch_taken),
        .pc_write       (pc_write),
        .if_id_write    (if_id_write),
        .id_ex_flush    (id_ex_flush),
        .if_id_flush    (if_id_flush)
    );

    // ══ forwarding unit ═══════════════════════════════════════════
    forwarding_unit u_fwd (
        .id_ex_rs1       (id_ex_rs1),
        .id_ex_rs2       (id_ex_rs2),
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_rd       (ex_mem_rd),
        .mem_wb_reg_write(mem_wb_reg_write),
        .mem_wb_rd       (mem_wb_rd),
        .forwardA        (forwardA),
        .forwardB        (forwardB)
    );

    // ══ debug output ══════════════════════════════════════════════
    // debug_out taken from a real port instead of a hierarchical
    // reference into the regfile array. The old form,
    //     assign debug_out = u_id.u_regfile.regs[10];
    // blocked LUTRAM inference and cost ~1700 LUTs + 1024 FFs.
    assign debug_out = dbg_x10_w;
    assign mem_stall_out = mem_stall;
    assign if_pc_out = if_pc;
    assign if_stall_out = if_stall;

endmodule : riscv_cpu_p4
// if_stage_axi.sv
// MINERVA P4.5 -- instruction fetch over AXI4-Lite.
//
// Replaces if_stage.sv's internal ROM (`assign instr = imem[pc_reg[11:2]]`,
// combinational, zero-latency) with a blocking AXI4-Lite read to crossbar
// slave 3 (imem, 0x0003_0000). This makes programs runtime-loadable over
// JTAG and -- the reason it matters for P5 -- makes instruction memory
// reachable by the fault-injection master, so faults can hit code and not
// just data.
//
// if_stage.sv is left UNTOUCHED. This is a separate module so the working,
// hardware-verified fetch path stays available for comparison and fallback.
//
// ============================ DESIGN NOTES ============================
//
// 1. WHY THE REDIRECT IS LATCHED, NOT GATED
//    riscv_cpu_p3 resolves branches at EX/MEM: pc_sel is driven by
//    ex_mem_branch_taken, which is a registered signal that advances (and
//    therefore deasserts) as soon as EX/MEM moves on. In the original
//    design the PC could always accept it immediately because fetch was
//    combinational.
//    With AXI fetch, the PC may be frozen mid-transaction when that pulse
//    arrives. Gating it through pc_write (the way mem_stall does) would
//    DROP the redirect and the CPU would continue down the wrong path --
//    a silent, intermittent, extremely painful bug.
//    So: any redirect seen while a fetch is outstanding is captured into
//    redirect_pending_q / redirect_target_q and applied when the current
//    transaction retires.
//
// 2. WHY IN-FLIGHT FETCHES ARE COMPLETED, NOT CANCELLED
//    AXI4-Lite has no abort mechanism. Once AR is accepted, the slave WILL
//    return R data. Dropping ARVALID early or ignoring RVALID desynchronises
//    the channel and wedges the crossbar's held grant. The fetch is always
//    run to completion; the DATA is discarded when it belongs to a
//    wrong-path PC.
//
// 3. RESET PC
//    Moves from 0x0000_0000 to IMEM_BASE, since 0x0000_0000 is now data
//    memory in the P4 map. Parameterised so it can't silently disagree
//    with the crossbar's SLAVE_BASE.

`include "axi4lite_ports.vh"

`timescale 1ns/1ps

module if_stage_axi #(
    parameter logic [31:0] IMEM_BASE = 32'h0003_0000,
    // Instruction inserted while a fetch is in flight. NOP = ADDI x0,x0,0,
    // same encoding riscv_cpu_p3 uses for its own flush bubbles.
    parameter logic [31:0] NOP_INSTR = 32'h0000_0013
)(
    input  logic        clk,
    input  logic        rst,          // ACTIVE HIGH, matches if_stage.sv
                                       // and riscv_cpu_p3's convention

    input  logic        pc_write,     // from hazard_unit, ANDed with
                                       // ~mem_stall by the parent
    input  logic        pc_sel,       // ex_mem_branch_taken (registered)
    input  logic [31:0] branch_target,

    output logic [31:0] instr,
    output logic [31:0] pc,
    output logic [31:0] pc_plus4,

    // High while a fetch is outstanding. Parent must fold this into its
    // pipeline enables exactly like mem_stall.
    output logic        if_stall,

    // AXI4-Lite master -> crossbar master port (instruction fetch)
    `AXI4LITE_MASTER_PORTS(i_axi)
);

    // ---------------- PC ----------------
    logic [31:0] pc_reg;
    logic [31:0] fetch_pc_q;      // PC of the transaction currently in flight

    // ---------------- redirect capture ----------------
    logic        redirect_pending_q;
    logic [31:0] redirect_target_q;

    // ---------------- fetch FSM ----------------
    // IF_START : one cycle after reset before issuing anything. See note 4.
    // IF_ISSUE : drive ARVALID for pc_reg
    // IF_WAIT  : ARVALID accepted, waiting on RVALID
    // IF_VALID : instruction available for exactly one cycle; pipeline
    //            advances, then straight back to IF_ISSUE for the next PC
    //
    // 4. WHY IF_START EXISTS
    //    axi4lite_mem_model (and Xilinx's BRAM controller) drive ARREADY
    //    from a continuous assign that is high even while the slave is
    //    held in reset, but the registered logic that actually captures
    //    the address is gated by reset. Issuing AR on the very first
    //    post-reset edge therefore gets "accepted" by a slave that never
    //    saw it -- ARVALID drops, no RVALID ever returns, and the fetch
    //    unit parks in IF_WAIT forever. One idle cycle removes the race.
    typedef enum logic [1:0] {IF_START, IF_ISSUE, IF_WAIT, IF_VALID} if_state_e;
    if_state_e state_q;

    logic [31:0] instr_q;

    // Write channel is unused -- instruction fetch never writes.
    assign i_axi_awaddr  = 32'd0;
    assign i_axi_awvalid = 1'b0;
    assign i_axi_wdata   = 32'd0;
    assign i_axi_wstrb   = 4'd0;
    assign i_axi_wvalid  = 1'b0;
    assign i_axi_bready  = 1'b1;   // tied high; no writes are ever issued,
                                   // so no BVALID can arrive, but leaving
                                   // this low would deadlock if one did.

    assign i_axi_araddr  = fetch_pc_q;
    assign i_axi_arvalid = (state_q == IF_ISSUE);
    assign i_axi_rready  = (state_q == IF_WAIT);

    // Pipeline sees a NOP while a fetch is outstanding, and the real
    // instruction only in IF_VALID.
    assign instr    = (state_q == IF_VALID) ? instr_q : NOP_INSTR;
    assign pc       = pc_reg;
    assign pc_plus4 = pc_reg + 32'd4;
    assign if_stall = (state_q != IF_VALID);

    // A redirect is visible now if pc_sel is asserted this cycle, or was
    // captured earlier while a fetch was in flight.
    wire        redirect_now    = pc_sel | redirect_pending_q;
    wire [31:0] redirect_addr   = pc_sel ? branch_target : redirect_target_q;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            pc_reg             <= IMEM_BASE;
            fetch_pc_q         <= IMEM_BASE;
            state_q            <= IF_START;
            instr_q            <= NOP_INSTR;
            redirect_pending_q <= 1'b0;
            redirect_target_q  <= IMEM_BASE;
        end else begin

            // ---- capture a redirect that arrives mid-fetch ----
            // Must latch unconditionally: pc_sel is a transient pulse from
            // EX/MEM and will be gone next cycle. See design note 1.
            // The latched redirect is itself what marks any in-flight
            // fetch as wrong-path, so no separate discard flag is needed
            // (an earlier version had one, and it could be written twice
            // in a single cycle -- the later write silently winning).
            if (pc_sel && (state_q != IF_VALID)) begin
                redirect_pending_q <= 1'b1;
                redirect_target_q  <= branch_target;
            end

            unique case (state_q)

                IF_START: begin
                    // One dead cycle so the slave's registered logic is
                    // definitely out of reset before the first AR.
                    state_q <= IF_ISSUE;
                end

                IF_ISSUE: begin
                    if (i_axi_arready) begin
                        state_q <= IF_WAIT;
                    end
                end

                IF_WAIT: begin
                    if (i_axi_rvalid) begin
                        if (redirect_now) begin
                            // Wrong-path data: consume it (AXI requires the
                            // handshake to complete) and immediately refetch
                            // from the redirect target. See design note 2.
                            pc_reg             <= redirect_addr;
                            fetch_pc_q         <= redirect_addr;
                            redirect_pending_q <= 1'b0;
                            state_q            <= IF_ISSUE;
                        end else begin
                            instr_q <= i_axi_rdata;
                            state_q <= IF_VALID;
                        end
                    end
                end

                IF_VALID: begin
                    // Instruction is being consumed this cycle. Choose the
                    // next PC with the same priority the original design
                    // used: redirect beats sequential.
                    if (redirect_now) begin
                        pc_reg             <= redirect_addr;
                        fetch_pc_q         <= redirect_addr;
                        redirect_pending_q <= 1'b0;
                        state_q            <= IF_ISSUE;
                    end else if (pc_write) begin
                        pc_reg     <= pc_reg + 32'd4;
                        fetch_pc_q <= pc_reg + 32'd4;
                        state_q    <= IF_ISSUE;
                    end
                    // pc_write low (load-use stall or mem_stall): hold the
                    // instruction here. Staying in IF_VALID keeps if_stall
                    // low so the parent's own stall logic governs, exactly
                    // as with the original combinational fetch.
                end

                default: state_q <= IF_ISSUE;
            endcase
        end
    end

endmodule : if_stage_axi
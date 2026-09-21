// hazard_unit.sv - stall and flush control
// Purely combinational - detects load-use hazards and branch flushes

module hazard_unit (
    // load-use hazard detection
    input  logic       id_ex_mem_read,
    input  logic [4:0] id_ex_rd,
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,
    // branch flush - two distinct timing points, both needed:
    input  logic       ex_branch_taken,     // combinational, valid the SAME
                                             // cycle the branch is in EX -
                                             // used to stop the instruction
                                             // currently in ID/EX (the one
                                             // right after the branch) from
                                             // ever entering EX
    input  logic       branch_taken,        // registered (EX/MEM), valid one
                                             // cycle later - used to redirect
                                             // IF and to squash whatever got
                                             // fetched in the meantime
    // stall outputs
    output logic       pc_write,      // 0 = freeze PC
    output logic       if_id_write,   // 0 = freeze IF/ID register
    output logic       id_ex_flush,   // 1 = insert NOP into ID/EX
    // flush outputs
    output logic       if_id_flush    // 1 = flush IF/ID on branch
);

    logic load_use_stall;

    // ── load-use hazard ───────────────────────────────────────────
    // EX stage has a load, and ID stage needs that register
    // one bubble required - forwarding cannot help here
    // (data isn't available until end of MEM stage)
    assign load_use_stall = id_ex_mem_read &&
                            ((id_ex_rd == if_id_rs1) ||
                             (id_ex_rd == if_id_rs2)) &&
                            (id_ex_rd != 5'b0);

    assign pc_write    = ~load_use_stall;
    assign if_id_write = ~load_use_stall;

    // id_ex_flush must fire at BOTH points where a wrong-path instruction
    // is about to be latched into ID/EX:
    //  1) ex_branch_taken (combinational, same cycle branch is in EX) -
    //     stops the instruction currently in IF/ID (about to move into
    //     ID/EX this edge) from ever entering EX.
    //  2) branch_taken (registered, one cycle later) - by this point
    //     IF/ID is *also* being flushed for next cycle, but IF/ID's
    //     CURRENT content this same cycle still unconditionally latches
    //     into ID/EX at this edge unless we separately suppress it here.
    assign id_ex_flush = load_use_stall | ex_branch_taken | branch_taken;

    // ── branch flush ──────────────────────────────────────────────
    // branch_taken here is the registered (EX/MEM) version, valid one
    // cycle after ex_branch_taken. IF/ID must be flushed at that point
    // to catch whatever got fetched during the intervening cycle,
    // before the redirected fetch (driven by this same registered
    // signal) lands.
    assign if_id_flush = branch_taken;

endmodule
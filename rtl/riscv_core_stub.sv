// -----------------------------------------------------------------------------
// riscv_core_stub.sv  --  Simplified 3-stage RV32I core used as the DUT
// for the UVM verification env.
//
// Stages:  IF  -> EX (decode + execute + mem)  -> WB (regfile write)
//
// This is NOT my main core.  The full 5-stage pipelined version lives in
// my riscv-cpu-sv repo.  This stub is the DUT I point the UVM env at --
// it's small enough that I can reason about corner cases by hand, and it
// has a "commit port" that the UVM monitor snoops to build transactions.
//
// Supports: R-type, I-type (ADDI/ORI/ANDI/XORI/SLTI/SLTIU/SLLI/SRLI/SRAI),
//           loads (LW only for this project), stores (SW only),
//           branches (BEQ/BNE/BLT/BGE/BLTU/BGEU), JAL, JALR, LUI, AUIPC.
//
// Not supported: CSRs, ECALL/EBREAK, byte/half loads/stores, mult/div.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module riscv_core_stub (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction-memory interface (TB owns the memory)
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // Data-memory interface
    output logic        dmem_read,
    output logic        dmem_write,
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,

    // Commit port -- monitor snoops this to build UVM transactions.
    // Pulses for one cycle per retired instruction.
    output logic        commit_valid,
    output logic [31:0] commit_pc,
    output logic [31:0] commit_instr,
    output logic [4:0]  commit_rd,
    output logic [31:0] commit_rdata,
    output logic        commit_is_branch,
    output logic        commit_branch_taken
);

    // -------------------------------------------------------------------------
    // IF stage
    // -------------------------------------------------------------------------
    logic [31:0] pc_q, pc_next;
    logic [31:0] if_pc, if_instr;
    logic        if_valid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_q     <= 32'h0;
            if_valid <= 1'b0;
            if_pc    <= 32'h0;
        end else begin
            pc_q     <= pc_next;
            if_valid <= 1'b1;
            if_pc    <= pc_q;
        end
    end

    assign imem_addr = pc_q;
    assign if_instr  = imem_rdata;

    // -------------------------------------------------------------------------
    // Decode (combinational, inside EX stage input)
    // -------------------------------------------------------------------------
    logic [6:0]  opcode;
    logic [4:0]  rd, rs1, rs2;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;

    assign opcode = if_instr[6:0];
    assign rd     = if_instr[11:7];
    assign funct3 = if_instr[14:12];
    assign rs1    = if_instr[19:15];
    assign rs2    = if_instr[24:20];
    assign funct7 = if_instr[31:25];

    assign imm_i = {{20{if_instr[31]}}, if_instr[31:20]};
    assign imm_s = {{20{if_instr[31]}}, if_instr[31:25], if_instr[11:7]};
    assign imm_b = {{19{if_instr[31]}}, if_instr[31], if_instr[7],
                    if_instr[30:25], if_instr[11:8], 1'b0};
    assign imm_u = {if_instr[31:12], 12'h0};
    assign imm_j = {{11{if_instr[31]}}, if_instr[31], if_instr[19:12],
                    if_instr[20], if_instr[30:21], 1'b0};

    // -------------------------------------------------------------------------
    // Register file
    // -------------------------------------------------------------------------
    logic [31:0] xregs [32];
    logic [31:0] rs1_val, rs2_val;

    // "async" read (combinational), sync write in WB
    assign rs1_val = (rs1 == 5'd0) ? 32'h0 : xregs[rs1];
    assign rs2_val = (rs2 == 5'd0) ? 32'h0 : xregs[rs2];

    // -------------------------------------------------------------------------
    // EX: ALU + branch + mem addr
    // -------------------------------------------------------------------------
    localparam logic [6:0] OP_R     = 7'b0110011;
    localparam logic [6:0] OP_I     = 7'b0010011;
    localparam logic [6:0] OP_LOAD  = 7'b0000011;
    localparam logic [6:0] OP_STORE = 7'b0100011;
    localparam logic [6:0] OP_BR    = 7'b1100011;
    localparam logic [6:0] OP_JAL   = 7'b1101111;
    localparam logic [6:0] OP_JALR  = 7'b1100111;
    localparam logic [6:0] OP_LUI   = 7'b0110111;
    localparam logic [6:0] OP_AUIPC = 7'b0010111;

    logic [31:0] alu_a, alu_b, alu_y;
    logic [3:0]  alu_op;
    logic        br_taken;
    logic        is_alu_sub;

    always_comb begin
        // Select ALU operands
        case (opcode)
            OP_R, OP_BR:                       begin alu_a = rs1_val;  alu_b = rs2_val; end
            OP_I, OP_LOAD:                     begin alu_a = rs1_val;  alu_b = imm_i;   end
            OP_STORE:                          begin alu_a = rs1_val;  alu_b = imm_s;   end
            OP_JAL:                            begin alu_a = if_pc;    alu_b = imm_j;   end
            OP_JALR:                           begin alu_a = rs1_val;  alu_b = imm_i;   end
            OP_LUI:                            begin alu_a = 32'h0;    alu_b = imm_u;   end
            OP_AUIPC:                          begin alu_a = if_pc;    alu_b = imm_u;   end
            default:                           begin alu_a = 32'h0;    alu_b = 32'h0;   end
        endcase

        // Pick ALU op
        is_alu_sub = (opcode == OP_R) && (funct7[5] == 1'b1) && (funct3 == 3'b000);
        case ({opcode, funct3})
            {OP_R,  3'b000}: alu_op = is_alu_sub ? 4'd1 : 4'd0;  // ADD or SUB
            {OP_R,  3'b111}, {OP_I, 3'b111}: alu_op = 4'd2;       // AND
            {OP_R,  3'b110}, {OP_I, 3'b110}: alu_op = 4'd3;       // OR
            {OP_R,  3'b100}, {OP_I, 3'b100}: alu_op = 4'd4;       // XOR
            {OP_R,  3'b001}, {OP_I, 3'b001}: alu_op = 4'd5;       // SLL
            {OP_R,  3'b101}, {OP_I, 3'b101}: alu_op = funct7[5] ? 4'd7 : 4'd6;  // SRA/SRL
            {OP_R,  3'b010}, {OP_I, 3'b010}: alu_op = 4'd8;       // SLT (signed)
            {OP_R,  3'b011}, {OP_I, 3'b011}: alu_op = 4'd9;       // SLTU
            {OP_I,  3'b000}: alu_op = 4'd0;                       // ADDI
            default:         alu_op = 4'd0;                       // default ADD
        endcase

        // ALU compute
        case (alu_op)
            4'd0: alu_y = alu_a + alu_b;
            4'd1: alu_y = alu_a - alu_b;
            4'd2: alu_y = alu_a & alu_b;
            4'd3: alu_y = alu_a | alu_b;
            4'd4: alu_y = alu_a ^ alu_b;
            4'd5: alu_y = alu_a << alu_b[4:0];
            4'd6: alu_y = alu_a >> alu_b[4:0];
            4'd7: alu_y = unsigned'($signed(alu_a) >>> alu_b[4:0]);
            4'd8: alu_y = ($signed(alu_a) < $signed(alu_b)) ? 32'h1 : 32'h0;
            4'd9: alu_y = (alu_a < alu_b) ? 32'h1 : 32'h0;
            default: alu_y = 32'h0;
        endcase

        // Branch decision
        br_taken = 1'b0;
        if (opcode == OP_BR) begin
            case (funct3)
                3'b000: br_taken = (rs1_val == rs2_val);                       // BEQ
                3'b001: br_taken = (rs1_val != rs2_val);                       // BNE
                3'b100: br_taken = ($signed(rs1_val) <  $signed(rs2_val));     // BLT
                3'b101: br_taken = ($signed(rs1_val) >= $signed(rs2_val));     // BGE
                3'b110: br_taken = (rs1_val <  rs2_val);                       // BLTU
                3'b111: br_taken = (rs1_val >= rs2_val);                       // BGEU
                default: br_taken = 1'b0;
            endcase
        end
    end

    // Memory interface
    assign dmem_addr  = alu_y;
    assign dmem_wdata = rs2_val;
    assign dmem_read  = if_valid && (opcode == OP_LOAD);
    assign dmem_write = if_valid && (opcode == OP_STORE);

    // Writeback value select
    logic [31:0] wb_val;
    always_comb begin
        case (opcode)
            OP_LOAD:           wb_val = dmem_rdata;
            OP_JAL, OP_JALR:   wb_val = if_pc + 32'd4;
            default:           wb_val = alu_y;
        endcase
    end

    // Does this opcode write the regfile?
    logic rf_we;
    always_comb begin
        case (opcode)
            OP_R, OP_I, OP_LOAD, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC: rf_we = 1'b1;
            default: rf_we = 1'b0;
        endcase
    end

    // Next PC
    always_comb begin
        case (opcode)
            OP_JAL:  pc_next = if_pc + imm_j;
            OP_JALR: pc_next = (rs1_val + imm_i) & ~32'h1;
            OP_BR:   pc_next = br_taken ? (if_pc + imm_b) : (pc_q + 32'd4);
            default: pc_next = pc_q + 32'd4;
        endcase
    end

    // -------------------------------------------------------------------------
    // WB
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++) xregs[i] <= 32'h0;
        end else begin
            xregs[0] <= 32'h0;    // x0 pinned
            if (if_valid && rf_we && rd != 5'd0) begin
                xregs[rd] <= wb_val;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Commit port  --  monitor samples this on each clock
    // -------------------------------------------------------------------------
    assign commit_valid        = if_valid;
    assign commit_pc           = if_pc;
    assign commit_instr        = if_instr;
    assign commit_rd           = rd;
    assign commit_rdata        = wb_val;
    assign commit_is_branch    = (opcode == OP_BR);
    assign commit_branch_taken = br_taken;

endmodule

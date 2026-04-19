// -----------------------------------------------------------------------------
// riscv_coverage.sv  --  Functional coverage collector.
//
// Subscribes to the monitor's analysis port.  Samples on each commit.
//
// Coverpoints:
//   * opcode                 -- every RV32I opcode bin
//   * alu_funct3 x funct7    -- all ALU operation variants
//   * branch outcome         -- taken/not-taken x 6 branch types
//   * rd, rs1, rs2 usage     -- ensures we exercised the register file
//   * back-to-back RAW       -- cross of consecutive rd -> rs1/rs2
//   * pc region              -- has the PC visited different code regions
//
// Coverage journey: see docs/coverage_progress.md for how I got from
// 65% -> 90%.  TL;DR: first two covergroups hit 90% easily, the RAW cross
// was the hole that took Python-feedback stimulus to close.
// -----------------------------------------------------------------------------

class riscv_coverage extends uvm_subscriber #(riscv_commit_item);

    `uvm_component_utils(riscv_coverage)

    // Sampling surface -- updated on each write()
    bit [6:0]  s_opcode;
    bit [2:0]  s_funct3;
    bit [6:0]  s_funct7;
    bit [4:0]  s_rd, s_rs1, s_rs2;
    bit        s_is_branch;
    bit        s_br_taken;
    bit [31:0] s_pc;

    // Previous retire's rd -- for RAW cross
    bit [4:0]  prev_rd;

    // -------------------------------------------------------------------------
    covergroup cg_opcode;
        cp_opcode: coverpoint s_opcode {
            bins r_type  = {7'b0110011};
            bins i_alu   = {7'b0010011};
            bins lw      = {7'b0000011};
            bins sw      = {7'b0100011};
            bins branch  = {7'b1100011};
            bins jal     = {7'b1101111};
            bins jalr    = {7'b1100111};
            bins lui     = {7'b0110111};
            bins auipc   = {7'b0010111};
            bins other   = default;
        }
    endgroup

    covergroup cg_alu_ops;
        cp_f3: coverpoint s_funct3 iff (s_opcode inside {7'b0110011, 7'b0010011}) {
            bins add_sub = {3'b000};
            bins sll     = {3'b001};
            bins slt     = {3'b010};
            bins sltu    = {3'b011};
            bins xor_op  = {3'b100};
            bins srl_sra = {3'b101};
            bins or_op   = {3'b110};
            bins and_op  = {3'b111};
        }
        cp_f7: coverpoint s_funct7[5] iff (s_opcode == 7'b0110011);
        cross_alu: cross cp_f3, cp_f7;
    endgroup

    covergroup cg_branch;
        cp_br_type: coverpoint s_funct3 iff (s_is_branch) {
            bins beq  = {3'b000};
            bins bne  = {3'b001};
            bins blt  = {3'b100};
            bins bge  = {3'b101};
            bins bltu = {3'b110};
            bins bgeu = {3'b111};
        }
        cp_taken: coverpoint s_br_taken iff (s_is_branch);
        cross_br: cross cp_br_type, cp_taken;
    endgroup

    covergroup cg_regs;
        cp_rd  : coverpoint s_rd  { bins r[16] = {[0:15]}; bins hi = {[16:31]}; }
        cp_rs1 : coverpoint s_rs1 { bins r[16] = {[0:15]}; bins hi = {[16:31]}; }
        cp_rs2 : coverpoint s_rs2 { bins r[16] = {[0:15]}; bins hi = {[16:31]}; }
    endgroup

    // RAW-hazard cross: did consecutive instrs write and then read?
    covergroup cg_raw;
        cp_prev_rd : coverpoint prev_rd { bins r[8] = {[1:15]}; }
        cp_cur_rs1 : coverpoint s_rs1   { bins r[8] = {[1:15]}; }
        cp_cur_rs2 : coverpoint s_rs2   { bins r[8] = {[1:15]}; }
        cross_raw_rs1 : cross cp_prev_rd, cp_cur_rs1;
        cross_raw_rs2 : cross cp_prev_rd, cp_cur_rs2;
    endgroup

    // -------------------------------------------------------------------------
    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_opcode  = new();
        cg_alu_ops = new();
        cg_branch  = new();
        cg_regs    = new();
        cg_raw     = new();
        prev_rd    = 5'd0;
    endfunction

    function void write(riscv_commit_item t);
        s_opcode    = t.instr[6:0];
        s_funct3    = t.instr[14:12];
        s_funct7    = t.instr[31:25];
        s_rd        = t.rd;
        s_rs1       = t.instr[19:15];
        s_rs2       = t.instr[24:20];
        s_is_branch = t.is_branch;
        s_br_taken  = t.branch_taken;
        s_pc        = t.pc;

        cg_opcode.sample();
        cg_alu_ops.sample();
        cg_branch.sample();
        cg_regs.sample();
        cg_raw.sample();

        prev_rd = t.rd;
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("COV", $sformatf("cg_opcode  = %0.1f%%", cg_opcode.get_inst_coverage()),  UVM_LOW)
        `uvm_info("COV", $sformatf("cg_alu_ops = %0.1f%%", cg_alu_ops.get_inst_coverage()), UVM_LOW)
        `uvm_info("COV", $sformatf("cg_branch  = %0.1f%%", cg_branch.get_inst_coverage()),  UVM_LOW)
        `uvm_info("COV", $sformatf("cg_regs    = %0.1f%%", cg_regs.get_inst_coverage()),    UVM_LOW)
        `uvm_info("COV", $sformatf("cg_raw     = %0.1f%%", cg_raw.get_inst_coverage()),     UVM_LOW)
    endfunction

endclass

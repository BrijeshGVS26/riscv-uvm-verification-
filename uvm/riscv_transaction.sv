// -----------------------------------------------------------------------------
// riscv_transaction.sv  --  UVM sequence item + committed-instr transaction.
//
// riscv_instr_item     -- driver puts these into imem as 32-bit words.
//                         Sequence produces streams of these.
//
// riscv_commit_item    -- monitor captures these from the commit port and
//                         pushes them to scoreboard + coverage.
// -----------------------------------------------------------------------------

class riscv_instr_item extends uvm_sequence_item;

    // Opcode class -- keeps constraints readable
    typedef enum int { OP_ALU_R, OP_ALU_I, OP_LOAD, OP_STORE,
                       OP_BRANCH, OP_JAL, OP_JALR, OP_LUI, OP_AUIPC } op_class_e;

    rand op_class_e op_class;
    rand bit [4:0]  rd;
    rand bit [4:0]  rs1;
    rand bit [4:0]  rs2;
    rand bit [2:0]  funct3;
    rand bit [6:0]  funct7;
    rand bit [11:0] imm12;       // for I-type / branches
    rand bit [19:0] imm20;       // for LUI/AUIPC/JAL

    // Encoded 32-bit instruction (filled in by post_randomize)
    bit [31:0] encoded;

    `uvm_object_utils_begin(riscv_instr_item)
        `uvm_field_int(encoded, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "riscv_instr_item");
        super.new(name);
    endfunction

    // --- Constraints ---------------------------------------------------------

    // Keep rd/rs1/rs2 in the low 16 regs to make RAW hazards more likely
    // (discovered the hard way that uniformly random 0..31 reg indices barely
    //  ever produce back-to-back dependencies).
    constraint c_reg_range {
        rd  inside {[0:15]};
        rs1 inside {[0:15]};
        rs2 inside {[0:15]};
    }

    // Funct3/funct7 only legal combinations.  I ran into a scoreboard false
    // failure from illegal encodings, so I constrain them here.
    constraint c_funct {
        if (op_class == OP_ALU_R) {
            funct3 inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
            funct7 inside {7'b0000000, 7'b0100000};
            // SUB/SRA (funct7=0100000) only legal for ADD/SUB and SRL/SRA slots
            if (funct7 == 7'b0100000) funct3 inside {3'b000, 3'b101};
        }
        if (op_class == OP_ALU_I) {
            funct3 inside {3'b000, 3'b001, 3'b010, 3'b011, 3'b100, 3'b101, 3'b110, 3'b111};
            // shift immediates use funct7 top bits
            if (funct3 inside {3'b001, 3'b101}) funct7 inside {7'b0000000, 7'b0100000};
            if (funct3 == 3'b001) funct7 == 7'b0000000;
        }
        if (op_class == OP_BRANCH) {
            funct3 inside {3'b000, 3'b001, 3'b100, 3'b101, 3'b110, 3'b111};
        }
        if (op_class == OP_LOAD) {
            funct3 == 3'b010;                 // LW only in this project
        }
        if (op_class == OP_STORE) {
            funct3 == 3'b010;                 // SW only
        }
    }

    // Branch offsets kept small -- full 12-bit branches can overrun my tiny
    // instruction memory.  Learned this when my first random run faulted
    // with PC=0xdeadbeef.
    constraint c_branch_imm {
        if (op_class == OP_BRANCH) imm12 inside {[12'h000 : 12'h040]};
    }

    // JAL/AUIPC/LUI upper immediates kept tiny for same reason
    constraint c_imm20 {
        if (op_class inside {OP_JAL, OP_LUI, OP_AUIPC})
            imm20 inside {[20'h00000 : 20'h00010]};
    }

    // Encode after randomization -------------------------------------------
    function void post_randomize();
        case (op_class)
            OP_ALU_R : encoded = {funct7, rs2, rs1, funct3, rd, 7'b0110011};
            OP_ALU_I : encoded = {imm12, rs1, funct3, rd, 7'b0010011};
            OP_LOAD  : encoded = {imm12, rs1, funct3, rd, 7'b0000011};
            OP_STORE : encoded = {imm12[11:5], rs2, rs1, funct3, imm12[4:0], 7'b0100011};
            OP_BRANCH: encoded = {imm12[11], imm12[9:4], rs2, rs1, funct3,
                                  imm12[3:0], imm12[10], 7'b1100011};
            OP_JAL   : encoded = {imm20[19], imm20[9:0], imm20[10], imm20[18:11],
                                  rd, 7'b1101111};
            OP_JALR  : encoded = {imm12, rs1, 3'b000, rd, 7'b1100111};
            OP_LUI   : encoded = {imm20, rd, 7'b0110111};
            OP_AUIPC : encoded = {imm20, rd, 7'b0010111};
            default  : encoded = 32'h00000013;  // NOP
        endcase
    endfunction

    function string convert2string();
        return $sformatf("op=%s rd=x%0d rs1=x%0d rs2=x%0d enc=%h",
                         op_class.name(), rd, rs1, rs2, encoded);
    endfunction

endclass


class riscv_commit_item extends uvm_sequence_item;

    bit [31:0] pc;
    bit [31:0] instr;
    bit [4:0]  rd;
    bit [31:0] rdata;        // value written to rd, if any
    bit        is_branch;
    bit        branch_taken;

    `uvm_object_utils_begin(riscv_commit_item)
        `uvm_field_int(pc,           UVM_ALL_ON)
        `uvm_field_int(instr,        UVM_ALL_ON)
        `uvm_field_int(rd,           UVM_ALL_ON)
        `uvm_field_int(rdata,        UVM_ALL_ON)
        `uvm_field_int(is_branch,    UVM_ALL_ON)
        `uvm_field_int(branch_taken, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "riscv_commit_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("PC=%h  instr=%h  x%0d<=%h  br=%0b taken=%0b",
                         pc, instr, rd, rdata, is_branch, branch_taken);
    endfunction

endclass

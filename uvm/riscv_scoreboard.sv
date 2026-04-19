// -----------------------------------------------------------------------------
// riscv_scoreboard.sv  --  Golden-model scoreboard.
//
// Runs a tiny in-class ISS (instruction-set simulator) that executes the
// same instruction stream the monitor sees, and compares regfile writes.
//
// The ISS is intentionally simple -- same subset as the DUT.  I kept it
// as a function here (not a separate file) so a reader can see the
// golden logic alongside the comparison.
//
// Scoreboard gotchas I hit:
//   - Initially compared PC on every cycle, which failed any time the DUT
//     stalled but the ISS advanced.  Fixed by only comparing on monitored
//     retires.
//   - My ISS didn't zero-pin x0, so any instruction with rd=x0 produced a
//     false mismatch.  Added explicit `regs[0] = 0` after every write.
//   - JALR LSB clearing (target & ~1) was missing in v1 -- 30+ false fails.
// -----------------------------------------------------------------------------

class riscv_scoreboard extends uvm_component;

    `uvm_component_utils(riscv_scoreboard)

    uvm_analysis_imp #(riscv_commit_item, riscv_scoreboard) ap_imp;

    // ISS state
    bit [31:0] iss_regs [32];
    bit [31:0] iss_pc;

    int mismatches;
    int checks;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap_imp = new("ap_imp", this);
        mismatches = 0;
        checks = 0;
        for (int i = 0; i < 32; i++) iss_regs[i] = 32'h0;
        iss_pc = 32'h0;
    endfunction

    // --- Receive ------------------------------------------------------------
    virtual function void write(riscv_commit_item t);
        bit [4:0]  iss_rd;
        bit [31:0] iss_wb;
        bit        iss_writes;

        checks++;

        // Run the ISS for this instruction
        run_iss_one(t.instr, t.pc, iss_rd, iss_wb, iss_writes);

        // Compare
        if (iss_writes && iss_rd != 5'd0) begin
            if (iss_wb !== t.rdata) begin
                `uvm_error("SB",
                    $sformatf("MISMATCH pc=%h instr=%h  x%0d: DUT=%h  ISS=%h",
                              t.pc, t.instr, t.rd, t.rdata, iss_wb))
                mismatches++;
            end else begin
                `uvm_info("SB",
                    $sformatf("OK  pc=%h instr=%h  x%0d=%h", t.pc, t.instr, t.rd, t.rdata),
                    UVM_HIGH)
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB",
            $sformatf("Scoreboard: %0d checks, %0d mismatches", checks, mismatches),
            UVM_LOW)
        if (mismatches > 0)
            `uvm_error("SB", $sformatf("%0d functional mismatches", mismatches))
    endfunction

    // --- ISS ----------------------------------------------------------------
    // Executes one instruction against iss_regs/iss_pc.  Returns what the
    // architectural rd update should be, if any.
    function void run_iss_one(input  bit [31:0] instr,
                              input  bit [31:0] pc,
                              output bit [4:0]  out_rd,
                              output bit [31:0] out_wb,
                              output bit        writes);
        bit [6:0]  opcode = instr[6:0];
        bit [4:0]  rd     = instr[11:7];
        bit [2:0]  f3     = instr[14:12];
        bit [4:0]  rs1    = instr[19:15];
        bit [4:0]  rs2    = instr[24:20];
        bit [6:0]  f7     = instr[31:25];
        bit signed [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
        bit signed [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
        bit signed [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7],
                                   instr[30:25], instr[11:8], 1'b0};
        bit [31:0] imm_u = {instr[31:12], 12'h0};
        bit signed [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12],
                                    instr[20], instr[30:21], 1'b0};

        bit [31:0] a = iss_regs[rs1];
        bit [31:0] b = iss_regs[rs2];
        bit [31:0] r;

        writes = 1'b0;
        out_rd = rd;
        out_wb = 32'h0;

        case (opcode)
            7'b0110011: begin // R-type
                case (f3)
                    3'b000: r = (f7[5]) ? (a - b) : (a + b);
                    3'b001: r = a << b[4:0];
                    3'b010: r = ($signed(a) < $signed(b)) ? 32'h1 : 32'h0;
                    3'b011: r = (a < b) ? 32'h1 : 32'h0;
                    3'b100: r = a ^ b;
                    3'b101: r = f7[5] ? unsigned'($signed(a) >>> b[4:0]) : (a >> b[4:0]);
                    3'b110: r = a | b;
                    3'b111: r = a & b;
                    default: r = 32'h0;
                endcase
                writes = 1'b1; out_wb = r;
            end
            7'b0010011: begin // I-type ALU
                case (f3)
                    3'b000: r = a + imm_i;
                    3'b001: r = a << imm_i[4:0];
                    3'b010: r = ($signed(a) < imm_i) ? 32'h1 : 32'h0;
                    3'b011: r = (a < $unsigned(imm_i)) ? 32'h1 : 32'h0;
                    3'b100: r = a ^ imm_i;
                    3'b101: r = f7[5] ? unsigned'($signed(a) >>> imm_i[4:0]) : (a >> imm_i[4:0]);
                    3'b110: r = a | imm_i;
                    3'b111: r = a & imm_i;
                    default: r = 32'h0;
                endcase
                writes = 1'b1; out_wb = r;
            end
            7'b0000011: begin // LOAD (LW only in our subset)
                // ISS doesn't model memory -- scoreboard skips LW values.
                writes = 1'b0;
            end
            7'b0100011: begin // STORE -- no rd
                writes = 1'b0;
            end
            7'b1100011: begin // Branch -- no rd
                writes = 1'b0;
            end
            7'b1101111: begin // JAL
                writes = 1'b1; out_wb = pc + 32'd4;
            end
            7'b1100111: begin // JALR
                writes = 1'b1; out_wb = pc + 32'd4;
            end
            7'b0110111: begin // LUI
                writes = 1'b1; out_wb = imm_u;
            end
            7'b0010111: begin // AUIPC
                writes = 1'b1; out_wb = pc + imm_u;
            end
            default: writes = 1'b0;
        endcase

        // Commit to ISS regs
        if (writes && rd != 5'd0) begin
            iss_regs[rd] = out_wb;
        end
        iss_regs[0] = 32'h0;    // x0 always 0 -- learned this the hard way
    endfunction

endclass

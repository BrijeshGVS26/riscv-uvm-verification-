// -----------------------------------------------------------------------------
// riscv_if.sv  --  Virtual interface for the UVM env.
//
// Carries the signals I want the driver to poke and the monitor to observe.
// The driver's real job is writing instructions into the TB-owned instruction
// memory BEFORE releasing reset -- so there's not much for it to "drive"
// during simulation.  Monitor is where most of the work happens.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

interface riscv_if (input logic clk);
    logic        rst_n;

    // Commit port from the DUT -- snooped by monitor
    logic        commit_valid;
    logic [31:0] commit_pc;
    logic [31:0] commit_instr;
    logic [4:0]  commit_rd;
    logic [31:0] commit_rdata;
    logic        commit_is_branch;
    logic        commit_branch_taken;

    // Regfile snoop -- monitor uses this to build the architectural state
    // picture that the scoreboard compares against the ISS.
    // (pulled from inside the DUT via hierarchical reference in tb_top)
    logic [31:0] arch_regs [32];

    clocking mon_cb @(posedge clk);
        input commit_valid, commit_pc, commit_instr, commit_rd, commit_rdata;
        input commit_is_branch, commit_branch_taken;
    endclocking

    modport MON (clocking mon_cb, input rst_n);
endinterface

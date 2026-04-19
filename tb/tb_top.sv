// -----------------------------------------------------------------------------
// tb_top.sv  --  Simulation top.  Clock, reset, DUT, imem/dmem models,
// virtual interface handoff to the UVM env.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import riscv_pkg::*;

    // Tests
    `include "riscv_base_test.sv"
    `include "riscv_random_test.sv"
    `include "riscv_raw_hazard_test.sv"
    `include "riscv_branch_test.sv"

    // --- Clock/reset --------------------------------------------------------
    logic clk = 0;
    always #5 clk = ~clk;           // 100 MHz

    // --- Interface ----------------------------------------------------------
    riscv_if vif (clk);
    initial vif.rst_n = 1'b0;       // driver releases reset later

    // --- Memories -----------------------------------------------------------
    logic [31:0] imem [0:4095];
    logic [31:0] dmem [0:4095];

    // imem read (sync)
    logic [31:0] imem_addr;
    logic [31:0] imem_rdata;
    always_ff @(posedge clk) imem_rdata <= imem[imem_addr[13:2]];

    // dmem r/w
    logic        dmem_read, dmem_write;
    logic [31:0] dmem_addr;
    logic [31:0] dmem_wdata;
    logic [31:0] dmem_rdata;
    always_ff @(posedge clk) begin
        if (dmem_write) dmem[dmem_addr[13:2]] <= dmem_wdata;
        dmem_rdata <= dmem[dmem_addr[13:2]];
    end

    // --- DUT ----------------------------------------------------------------
    riscv_core_stub dut (
        .clk                 (clk),
        .rst_n               (vif.rst_n),
        .imem_addr           (imem_addr),
        .imem_rdata          (imem_rdata),
        .dmem_read           (dmem_read),
        .dmem_write          (dmem_write),
        .dmem_addr           (dmem_addr),
        .dmem_wdata          (dmem_wdata),
        .dmem_rdata          (dmem_rdata),
        .commit_valid        (vif.commit_valid),
        .commit_pc           (vif.commit_pc),
        .commit_instr        (vif.commit_instr),
        .commit_rd           (vif.commit_rd),
        .commit_rdata        (vif.commit_rdata),
        .commit_is_branch    (vif.commit_is_branch),
        .commit_branch_taken (vif.commit_branch_taken)
    );

    // Snoop the DUT's architectural regs for post-mortem debug
    always_comb for (int i = 0; i < 32; i++) vif.arch_regs[i] = dut.xregs[i];

    // --- UVM kickoff --------------------------------------------------------
    initial begin
        uvm_config_db#(virtual riscv_if)::set(null, "*", "vif", vif);

        // The driver pokes imem via config_db entries "imem_w_<idx>".
        // Harvest them here into the real imem array before run_phase.
        // (Not elegant but it keeps the driver UVM-shaped.)
        fork
            forever begin
                #1;
                for (int i = 0; i < 256; i++) begin
                    bit [31:0] v;
                    if (uvm_config_db#(bit [31:0])::get(null, "", $sformatf("imem_w_%0d", i), v))
                        imem[i] = v;
                end
            end
        join_none

        // Pre-fill imem with NOPs (ADDI x0,x0,0) so unwritten slots are safe
        for (int i = 0; i < 4096; i++) imem[i] = 32'h00000013;

        run_test();
    end

    // Dump
    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
    end

endmodule

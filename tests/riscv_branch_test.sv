// -----------------------------------------------------------------------------
// riscv_branch_test.sv  --  branch-heavy.  Closes branch-taken coverage holes.
// -----------------------------------------------------------------------------

class riscv_branch_test extends riscv_base_test;

    `uvm_component_utils(riscv_branch_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_sequence();
        riscv_branch_seq seq;
        seq = riscv_branch_seq::type_id::create("br_seq");
        if (!seq.randomize() with { num_instr == 200; })
            `uvm_error("TEST", "randomize failed")
        seq.start(env.agt.sqr);
    endtask

endclass

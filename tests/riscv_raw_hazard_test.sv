// -----------------------------------------------------------------------------
// riscv_raw_hazard_test.sv  --  hammer back-to-back register dependencies.
// Exposed the load-use hazard bug in my first stub -- see docs/bugs_found.md.
// -----------------------------------------------------------------------------

class riscv_raw_hazard_test extends riscv_base_test;

    `uvm_component_utils(riscv_raw_hazard_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_sequence();
        riscv_raw_seq seq;
        seq = riscv_raw_seq::type_id::create("raw_seq");
        if (!seq.randomize() with { num_instr == 150; })
            `uvm_error("TEST", "randomize failed")
        seq.start(env.agt.sqr);
    endtask

endclass

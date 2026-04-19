// -----------------------------------------------------------------------------
// riscv_random_test.sv  --  balanced constrained-random instruction mix.
// This is the nightly regression driver.
// -----------------------------------------------------------------------------

class riscv_random_test extends riscv_base_test;

    `uvm_component_utils(riscv_random_test)

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    task run_sequence();
        riscv_base_seq seq;
        seq = riscv_base_seq::type_id::create("rand_seq");
        if (!seq.randomize() with { num_instr == 200; })
            `uvm_error("TEST", "randomize failed")
        seq.start(env.agt.sqr);
    endtask

endclass

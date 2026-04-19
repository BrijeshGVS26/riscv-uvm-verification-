// -----------------------------------------------------------------------------
// riscv_base_test.sv  --  base class for all tests.  Instantiates the env,
// owns the objection, and provides a default sequence hook.
// -----------------------------------------------------------------------------

class riscv_base_test extends uvm_test;

    `uvm_component_utils(riscv_base_test)

    riscv_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = riscv_env::type_id::create("env", this);
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_sequence();
        // give a cushion for the DUT to actually retire the stream
        #50_000;
        phase.drop_objection(this);
    endtask

    // Subclasses override to start a specific sequence
    virtual task run_sequence();
        riscv_base_seq seq;
        seq = riscv_base_seq::type_id::create("seq");
        seq.start(env.agt.sqr);
    endtask

endclass

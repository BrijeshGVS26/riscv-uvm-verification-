// -----------------------------------------------------------------------------
// riscv_sequence.sv  --  Sequences of instructions for the driver.
//
// Each sequence produces N riscv_instr_items that the driver writes into the
// TB instruction memory in order, then releases reset.
//
// Flavors:
//   riscv_random_seq     -- plain constrained-random mix
//   riscv_raw_seq        -- biased toward back-to-back register dependencies
//   riscv_branch_seq     -- biased toward branches + short loops
//   riscv_mixed_seq      -- 1000-instr mix, used in nightly regression
//
// Weights are overridable from the test (and from the Python stim tuner).
// -----------------------------------------------------------------------------

class riscv_base_seq extends uvm_sequence #(riscv_instr_item);

    `uvm_object_utils(riscv_base_seq)

    rand int unsigned num_instr;

    // Per-opclass weights (read from uvm_config_db so the Python tuner can
    // inject them).  Default: balanced.
    int w_r      = 30;
    int w_i      = 30;
    int w_load   = 10;
    int w_store  = 10;
    int w_branch = 10;
    int w_jal    = 5;
    int w_jalr   = 3;
    int w_lui    = 1;
    int w_auipc  = 1;

    constraint c_num { num_instr inside {[32:256]}; }

    function new(string name = "riscv_base_seq");
        super.new(name);
    endfunction

    virtual task body();
        riscv_instr_item tr;

        // Pull weight overrides from config_db if the test set any
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_r",      w_r));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_i",      w_i));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_load",   w_load));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_store",  w_store));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_branch", w_branch));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_jal",    w_jal));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_jalr",   w_jalr));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_lui",    w_lui));
        void'(uvm_config_db#(int)::get(null, get_full_name(), "w_auipc",  w_auipc));

        `uvm_info("SEQ", $sformatf("Starting %0d instructions", num_instr), UVM_LOW)

        for (int i = 0; i < num_instr; i++) begin
            tr = riscv_instr_item::type_id::create($sformatf("tr_%0d", i));
            start_item(tr);
            if (!tr.randomize() with {
                op_class dist {
                    riscv_instr_item::OP_ALU_R  := w_r,
                    riscv_instr_item::OP_ALU_I  := w_i,
                    riscv_instr_item::OP_LOAD   := w_load,
                    riscv_instr_item::OP_STORE  := w_store,
                    riscv_instr_item::OP_BRANCH := w_branch,
                    riscv_instr_item::OP_JAL    := w_jal,
                    riscv_instr_item::OP_JALR   := w_jalr,
                    riscv_instr_item::OP_LUI    := w_lui,
                    riscv_instr_item::OP_AUIPC  := w_auipc
                };
            }) `uvm_error("SEQ", "randomize failed")
            finish_item(tr);
        end
    endtask

endclass


// Biased toward R-type with tight register dependencies (RAW hazards)
class riscv_raw_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_raw_seq)
    function new(string name = "riscv_raw_seq");
        super.new(name);
        w_r      = 70;
        w_i      = 20;
        w_load   = 10;
        w_store  = 0;
        w_branch = 0;
        w_jal    = 0;
        w_jalr   = 0;
    endfunction
endclass


// Biased toward branches -- small jump range + lots of BEQ/BNE
class riscv_branch_seq extends riscv_base_seq;
    `uvm_object_utils(riscv_branch_seq)
    function new(string name = "riscv_branch_seq");
        super.new(name);
        w_r      = 30;
        w_i      = 20;
        w_branch = 50;
    endfunction
endclass

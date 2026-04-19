// -----------------------------------------------------------------------------
// riscv_driver.sv  --  Pulls instr items from the sequencer and writes them
// into the TB-owned instruction memory, then releases reset.
//
// NOTE: this is not a classic "per-cycle" driver.  The DUT reads instructions
// from imem itself -- the driver's job is to populate imem before the core
// starts running.  Writing it as a driver anyway so the env stays
// UVM-conventional.
// -----------------------------------------------------------------------------

class riscv_driver extends uvm_driver #(riscv_instr_item);

    `uvm_component_utils(riscv_driver)

    // Handle to the TB's imem array, set via config_db in tb_top
    typedef bit [31:0] imem_t [0:4095];
    imem_t imem_h;    // local copy, written back at end of program

    virtual riscv_if vif;
    int instr_count;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif))
            `uvm_fatal("DRV", "no vif in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        riscv_instr_item tr;

        // Build the instruction stream, then release reset so the DUT runs it.
        // The driver doesn't pulse anything per instruction -- the DUT fetches
        // at its own pace.
        instr_count = 0;

        // Collect items from the sequencer
        forever begin
            seq_item_port.get_next_item(tr);
            write_imem(instr_count * 4, tr.encoded);
            `uvm_info("DRV", $sformatf("imem[%0d] <= %s", instr_count, tr.convert2string()), UVM_HIGH)
            instr_count++;
            seq_item_port.item_done();
            // break out when we hit a reasonable cap
            if (instr_count >= 256) break;
        end

        // Terminate the program with an infinite-loop marker
        // (the scoreboard watches for PC stuck = test done)
        write_imem(instr_count * 4, 32'h0000006F);  // JAL x0, 0  -> self-loop

        `uvm_info("DRV", $sformatf("Program built (%0d instructions). Releasing reset.", instr_count), UVM_LOW)

        // Kick reset low-high so the DUT starts fetching
        vif.rst_n = 1'b0;
        repeat (10) @(posedge vif.clk);
        vif.rst_n = 1'b1;

        // Wait for program to finish (scoreboard decides)
        // Just wait "long enough" here -- the test decides when to call
        // phase.drop_objection.
        repeat (instr_count * 20) @(posedge vif.clk);
    endtask

    // Hierarchical poke into the TB's imem.  Not elegant but it works.
    virtual function void write_imem(int addr, bit [31:0] data);
        uvm_config_db#(bit [31:0])::set(null, "*", $sformatf("imem_w_%0d", addr>>2), data);
    endfunction

endclass

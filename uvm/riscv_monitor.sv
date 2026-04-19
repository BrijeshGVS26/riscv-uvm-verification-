// -----------------------------------------------------------------------------
// riscv_monitor.sv  --  Snoops the DUT commit port and publishes
// riscv_commit_item transactions on its analysis port.  Scoreboard and
// coverage both subscribe.
//
// Subtle thing I tripped on: the DUT drives `commit_valid` every cycle
// where IF has a valid instruction.  For real regression you'd want to gate
// this by an architectural-retire signal.  My first monitor was producing
// one txn per cycle = 1000 txns/ns, and the scoreboard queue overflowed.
// Fix: only emit when pc != last_pc (PC actually advanced).
// -----------------------------------------------------------------------------

class riscv_monitor extends uvm_monitor;

    `uvm_component_utils(riscv_monitor)

    virtual riscv_if vif;
    uvm_analysis_port #(riscv_commit_item) ap;

    bit [31:0] last_pc = 32'hffff_ffff;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual riscv_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "no vif in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        riscv_commit_item t;
        forever begin
            @(vif.mon_cb);
            if (vif.rst_n && vif.mon_cb.commit_valid &&
                vif.mon_cb.commit_pc !== last_pc) begin

                t = riscv_commit_item::type_id::create("t");
                t.pc           = vif.mon_cb.commit_pc;
                t.instr        = vif.mon_cb.commit_instr;
                t.rd           = vif.mon_cb.commit_rd;
                t.rdata        = vif.mon_cb.commit_rdata;
                t.is_branch    = vif.mon_cb.commit_is_branch;
                t.branch_taken = vif.mon_cb.commit_branch_taken;

                `uvm_info("MON", t.convert2string(), UVM_HIGH)
                ap.write(t);

                last_pc = vif.mon_cb.commit_pc;
            end
        end
    endtask

endclass

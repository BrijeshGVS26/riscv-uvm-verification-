// -----------------------------------------------------------------------------
// riscv_agent.sv  --  Active agent: sequencer + driver + monitor.
// -----------------------------------------------------------------------------

class riscv_agent extends uvm_agent;

    `uvm_component_utils(riscv_agent)

    uvm_sequencer #(riscv_instr_item) sqr;
    riscv_driver  drv;
    riscv_monitor mon;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sqr = uvm_sequencer#(riscv_instr_item)::type_id::create("sqr", this);
        drv = riscv_driver::type_id::create("drv", this);
        mon = riscv_monitor::type_id::create("mon", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction

endclass

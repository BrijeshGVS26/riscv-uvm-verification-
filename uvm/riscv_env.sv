// -----------------------------------------------------------------------------
// riscv_env.sv  --  Top-level UVM env.  Wires the monitor's analysis port to
// the scoreboard and the coverage collector.
// -----------------------------------------------------------------------------

class riscv_env extends uvm_env;

    `uvm_component_utils(riscv_env)

    riscv_agent      agt;
    riscv_scoreboard sb;
    riscv_coverage   cov;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        agt = riscv_agent::type_id::create("agt", this);
        sb  = riscv_scoreboard::type_id::create("sb",  this);
        cov = riscv_coverage::type_id::create("cov", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        agt.mon.ap.connect(sb.ap_imp);
        agt.mon.ap.connect(cov.analysis_export);
    endfunction

endclass

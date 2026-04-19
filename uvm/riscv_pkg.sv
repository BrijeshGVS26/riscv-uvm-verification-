// -----------------------------------------------------------------------------
// riscv_pkg.sv  --  Package all UVM classes together so `import riscv_pkg::*`
// pulls everything in.
// -----------------------------------------------------------------------------

package riscv_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    `include "riscv_transaction.sv"
    `include "riscv_sequence.sv"
    `include "riscv_driver.sv"
    `include "riscv_monitor.sv"
    `include "riscv_scoreboard.sv"
    `include "riscv_coverage.sv"
    `include "riscv_agent.sv"
    `include "riscv_env.sv"

endpackage

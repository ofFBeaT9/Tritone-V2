//==============================================================================
// Ternary Hazard Detection Unit
//
// Detects pipeline hazards and generates stall/flush signals
// - RAW (Read-After-Write) hazards
// - Load-use hazards
// - Branch hazards
//==============================================================================

`include "ternary_defs.vh"

module ternary_hazard_unit (
  // ID stage inputs (instruction being decoded)
  input  wire [5:0]  id_rs1,        // Source register 1 address (3 trits = 6 bits)
  input  wire [5:0]  id_rs2,        // Source register 2 address
  input  wire        id_uses_rs1,   // ID stage uses rs1
  input  wire        id_uses_rs2,   // ID stage uses rs2

  // EX stage inputs (instruction currently executing)
  input  wire [5:0]  ex_rd,         // Destination register address
  input  wire        ex_reg_write,  // EX stage will write register
  input  wire        ex_mem_read,   // EX stage is a load instruction

  // MEM stage inputs (instruction in memory stage)
  input  wire [5:0]  mem_rd,        // Destination register address
  input  wire        mem_reg_write, // MEM stage will write register

  // Hazard outputs
  output wire        pc_stall,      // Stall PC (freeze fetch)
  output wire        if_id_stall,   // Stall IF/ID pipeline register
  output wire        id_ex_flush    // Flush ID/EX pipeline register (insert bubble)
);

  // Helper function to compare ternary addresses (3 trits = 6 bits)
  function addr_match;
    input [5:0] a;
    input [5:0] b;
    begin
      addr_match = (a[1:0] == b[1:0]) && (a[3:2] == b[3:2]) && (a[5:4] == b[5:4]);
    end
  endfunction

  // Helper function to check if address is R0 (hardwired zero, never a hazard)
  function is_r0;
    input [5:0] addr;
    begin
      is_r0 = (addr[1:0] == `T_ZERO) && (addr[3:2] == `T_ZERO) && (addr[5:4] == `T_ZERO);
    end
  endfunction

  // RAW hazard detection
  wire raw_hazard_ex_rs1 = id_uses_rs1 && ex_reg_write &&
                           addr_match(id_rs1, ex_rd) && !is_r0(ex_rd);
  wire raw_hazard_ex_rs2 = id_uses_rs2 && ex_reg_write &&
                           addr_match(id_rs2, ex_rd) && !is_r0(ex_rd);

  // Detect RAW hazards with MEM stage (unused but kept for completeness)
  wire raw_hazard_mem_rs1 = id_uses_rs1 && mem_reg_write &&
                            addr_match(id_rs1, mem_rd) && !is_r0(mem_rd);
  wire raw_hazard_mem_rs2 = id_uses_rs2 && mem_reg_write &&
                            addr_match(id_rs2, mem_rd) && !is_r0(mem_rd);

  // Load-use hazard: EX stage is loading data, ID stage needs it
  // Cannot forward load data until MEM stage, so must stall
  wire load_use_hazard = ex_mem_read &&
                         ((raw_hazard_ex_rs1) || (raw_hazard_ex_rs2));

  // Stall pipeline if load-use hazard detected
  assign pc_stall = load_use_hazard;
  assign if_id_stall = load_use_hazard;
  assign id_ex_flush = load_use_hazard;

  // Note: Non-load RAW hazards will be handled by forwarding unit
  // If forwarding is not available, additional stalls may be needed

endmodule

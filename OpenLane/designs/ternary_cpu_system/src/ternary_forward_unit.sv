//==============================================================================
// Ternary Data Forwarding Unit
//
// Manages data forwarding from EX and MEM stages to resolve RAW hazards
// without stalling the pipeline.
//
// Forwarding Priority:
//   1. EX stage (most recent)
//   2. MEM stage
//   3. No forwarding (use register file value)
//==============================================================================

`include "ternary_defs.vh"

module ternary_forward_unit (
  // EX stage inputs (operands being used)
  input  wire [5:0]  ex_rs1,        // Source register 1 address in EX (3 trits = 6 bits)
  input  wire [5:0]  ex_rs2,        // Source register 2 address in EX

  // MEM stage inputs (potential forwarding source)
  input  wire [5:0]  mem_rd,        // Destination register in MEM
  input  wire        mem_reg_write, // MEM stage will write register

  // WB stage inputs (potential forwarding source)
  input  wire [5:0]  wb_rd,         // Destination register in WB
  input  wire        wb_reg_write,  // WB stage will write register

  // Forwarding control outputs
  output wire [1:0]  forward_a,     // Forward control for operand A (rs1)
  output wire [1:0]  forward_b      // Forward control for operand B (rs2)
);

  // Forward control encoding:
  // 2'b00 = No forwarding (use value from register file)
  // 2'b01 = Forward from WB stage
  // 2'b10 = Forward from MEM stage
  // 2'b11 = Reserved (not used)

  // Helper function to compare ternary addresses (3 trits = 6 bits)
  function addr_match;
    input [5:0] a;
    input [5:0] b;
    begin
      addr_match = (a[1:0] == b[1:0]) && (a[3:2] == b[3:2]) && (a[5:4] == b[5:4]);
    end
  endfunction

  // Helper function to check if address is R0 (never needs forwarding)
  function is_r0;
    input [5:0] addr;
    begin
      is_r0 = (addr[1:0] == `T_ZERO) && (addr[3:2] == `T_ZERO) && (addr[5:4] == `T_ZERO);
    end
  endfunction

  // Forwarding conditions
  wire mem_fwd_a = mem_reg_write && addr_match(ex_rs1, mem_rd) && !is_r0(mem_rd);
  wire mem_fwd_b = mem_reg_write && addr_match(ex_rs2, mem_rd) && !is_r0(mem_rd);
  wire wb_fwd_a  = wb_reg_write && addr_match(ex_rs1, wb_rd) && !is_r0(wb_rd);
  wire wb_fwd_b  = wb_reg_write && addr_match(ex_rs2, wb_rd) && !is_r0(wb_rd);

  // Forwarding control (MEM has priority over WB)
  assign forward_a = mem_fwd_a ? 2'b10 : (wb_fwd_a ? 2'b01 : 2'b00);
  assign forward_b = mem_fwd_b ? 2'b10 : (wb_fwd_b ? 2'b01 : 2'b00);

endmodule

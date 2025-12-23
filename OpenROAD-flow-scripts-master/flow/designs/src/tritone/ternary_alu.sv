// Balanced Ternary ALU
// 8-trit datapath with multiple operations
//
// Operations:
// 000 - ADD: a + b
// 001 - SUB: a - b (a + (-b))
// 010 - NEG: -a (ternary negation)
// 011 - MIN: trit-wise MIN(a, b) - AND-like
// 100 - MAX: trit-wise MAX(a, b) - OR-like
// 101 - SHL: shift left (multiply by 3)
// 110 - SHR: shift right (divide by 3)
// 111 - CMP: compare a and b (result = a - b for flags)

`include "ternary_defs.vh"

module ternary_alu #(
  parameter WIDTH = 8
)(
  input  wire [WIDTH*2-1:0] a,
  input  wire [WIDTH*2-1:0] b,
  input  wire [2:0]         op,
  output reg  [WIDTH*2-1:0] result,
  output wire [1:0]         carry,
  output wire               zero_flag,
  output wire               neg_flag
);

  // Operation codes
  localparam [2:0] OP_ADD = 3'b000;
  localparam [2:0] OP_SUB = 3'b001;
  localparam [2:0] OP_NEG = 3'b010;
  localparam [2:0] OP_MIN = 3'b011;
  localparam [2:0] OP_MAX = 3'b100;
  localparam [2:0] OP_SHL = 3'b101;
  localparam [2:0] OP_SHR = 3'b110;
  localparam [2:0] OP_CMP = 3'b111;

  // Internal signals
  wire [WIDTH*2-1:0] b_negated;
  wire [WIDTH*2-1:0] add_result;
  reg  [WIDTH*2-1:0] min_result;
  reg  [WIDTH*2-1:0] max_result;
  reg  [WIDTH*2-1:0] neg_result;
  wire [WIDTH*2-1:0] shl_result;
  wire [WIDTH*2-1:0] shr_result;
  wire [1:0]         add_carry;

  // Trit negation function
  function [1:0] t_neg;
    input [1:0] trit;
    begin
      case (trit)
        `T_NEG_ONE: t_neg = `T_POS_ONE;
        `T_ZERO:    t_neg = `T_ZERO;
        `T_POS_ONE: t_neg = `T_NEG_ONE;
        default:    t_neg = `T_INVALID;
      endcase
    end
  endfunction

  // Trit MIN function (AND-like)
  function [1:0] t_min;
    input [1:0] a_trit;
    input [1:0] b_trit;
    begin
      if (a_trit == `T_INVALID || b_trit == `T_INVALID)
        t_min = `T_INVALID;
      else if (a_trit == `T_NEG_ONE || b_trit == `T_NEG_ONE)
        t_min = `T_NEG_ONE;
      else if (a_trit == `T_ZERO || b_trit == `T_ZERO)
        t_min = `T_ZERO;
      else
        t_min = `T_POS_ONE;
    end
  endfunction

  // Trit MAX function (OR-like)
  function [1:0] t_max;
    input [1:0] a_trit;
    input [1:0] b_trit;
    begin
      if (a_trit == `T_INVALID || b_trit == `T_INVALID)
        t_max = `T_INVALID;
      else if (a_trit == `T_POS_ONE || b_trit == `T_POS_ONE)
        t_max = `T_POS_ONE;
      else if (a_trit == `T_ZERO || b_trit == `T_ZERO)
        t_max = `T_ZERO;
      else
        t_max = `T_NEG_ONE;
    end
  endfunction

  // Negate B for subtraction
  genvar i;
  generate
    for (i = 0; i < WIDTH; i = i + 1) begin : gen_neg_b
      assign b_negated[i*2+1:i*2] = t_neg(b[i*2+1:i*2]);
    end
  endgenerate

  // Select adder input B (original or negated)
  wire [WIDTH*2-1:0] adder_b;
  assign adder_b = (op == OP_SUB || op == OP_CMP) ? b_negated : b;

  // Adder (used for ADD, SUB, and CMP)
  ternary_adder #(.WIDTH(WIDTH)) u_adder (
    .a    (a),
    .b    (adder_b),
    .cin  (`T_ZERO),
    .sum  (add_result),
    .cout (add_carry)
  );

  // Bitwise operations
  integer j;
  always @(*) begin
    for (j = 0; j < WIDTH; j = j + 1) begin
      neg_result[j*2 +: 2] = t_neg(a[j*2 +: 2]);
      min_result[j*2 +: 2] = t_min(a[j*2 +: 2], b[j*2 +: 2]);
      max_result[j*2 +: 2] = t_max(a[j*2 +: 2], b[j*2 +: 2]);
    end
  end

  // Shift operations
  assign shl_result = {a[WIDTH*2-3:0], `T_ZERO};    // Shift left, insert 0
  assign shr_result = {`T_ZERO, a[WIDTH*2-1:2]};    // Shift right, insert 0

  // Output multiplexer
  always @(*) begin
    case (op)
      OP_ADD: result = add_result;
      OP_SUB: result = add_result;
      OP_NEG: result = neg_result;
      OP_MIN: result = min_result;
      OP_MAX: result = max_result;
      OP_SHL: result = shl_result;
      OP_SHR: result = shr_result;
      OP_CMP: result = add_result;
      default: result = {WIDTH*2{1'b1}};  // Invalid
    endcase
  end

  // Carry output
  assign carry = (op == OP_ADD || op == OP_SUB || op == OP_CMP) ? add_carry : `T_ZERO;

  // Zero flag: check if all trits are zero
  reg all_zero;
  integer k;
  always @(*) begin
    all_zero = 1'b1;
    for (k = 0; k < WIDTH; k = k + 1) begin
      if (result[k*2 +: 2] != `T_ZERO) all_zero = 1'b0;
    end
  end
  assign zero_flag = all_zero;

  // Negative flag: check MSB
  assign neg_flag = (result[WIDTH*2-1:WIDTH*2-2] == `T_NEG_ONE);

endmodule

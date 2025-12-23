// Balanced Ternary CPU Core - Dual-Issue Superscalar
// 4-stage pipeline: IF -> ID -> EX -> WB
// Dual-issue: Two instructions fetched and executed per cycle (when possible)
//
// BTISA v0.1 Implementation
// - 27-trit data path
// - 9 general-purpose registers
// - 9-trit instruction encoding
// - Symmetric dual-issue (both slots can execute any instruction)

`include "ternary_defs.vh"

module ternary_cpu #(
  parameter TRIT_WIDTH = 27
)(
  input  wire        clk,
  input  wire        rst_n,

  // Instruction memory interface (dual-issue: 2 instructions = 18 trits)
  output wire [15:0]              imem_addr,      // 8 trits = 16 bits
  input  wire [35:0]              imem_data,      // 18 trits = 36 bits [Slot A: 17:0, Slot B: 35:18]

  // Data memory interface (single port - Slot A has priority)
  output wire [17:0]              dmem_addr,      // 9 trits = 18 bits
  output wire [TRIT_WIDTH*2-1:0]  dmem_wdata,     // 27 trits = 54 bits
  input  wire [TRIT_WIDTH*2-1:0]  dmem_rdata,     // 27 trits = 54 bits
  output wire                     dmem_we,
  output wire                     dmem_re,

  // Status outputs
  output wire                     halted,
  output wire [15:0]              pc_out,         // 8 trits = 16 bits
  output wire                     valid_out_a,    // Slot A valid signal
  output wire                     valid_out_b,    // Slot B valid signal
  output wire [1:0]               ipc_out,        // Instructions per cycle (0, 1, or 2)

  // Debug ports for register file access
  input  wire [3:0]               dbg_reg_idx,    // 2 trits = 4 bits
  output wire [TRIT_WIDTH*2-1:0]  dbg_reg_data,   // 27 trits = 54 bits

  // Hazard status
  output wire                     stall_out,
  output wire                     fwd_a_out,
  output wire                     fwd_b_out
);

  // ============================================================
  // Pipeline Registers - Dual-Issue (Slot A and Slot B)
  // ============================================================

  // IF/ID Stage - Slot A
  reg  [17:0] if_id_instr_a;        // 9 trits = 18 bits
  reg  [15:0] if_id_pc_a;           // 8 trits = 16 bits
  reg         if_id_valid_a;

  // IF/ID Stage - Slot B
  reg  [17:0] if_id_instr_b;        // 9 trits = 18 bits
  reg  [15:0] if_id_pc_b;           // 8 trits = 16 bits
  reg         if_id_valid_b;

  // ID/EX Stage - Slot A
  reg  [TRIT_WIDTH*2-1:0] id_ex_rs1_data_a;  // 27 trits = 54 bits
  reg  [TRIT_WIDTH*2-1:0] id_ex_rs2_data_a;  // 27 trits = 54 bits
  reg  [3:0]              id_ex_rd_a;         // 2 trits = 4 bits
  reg  [3:0]              id_ex_rs1_a;        // 2 trits = 4 bits
  reg  [3:0]              id_ex_imm_a;        // 2 trits = 4 bits
  reg  [2:0]              id_ex_alu_op_a;
  reg                     id_ex_reg_write_a;
  reg                     id_ex_mem_read_a;
  reg                     id_ex_mem_write_a;
  reg                     id_ex_alu_src_a;
  reg                     id_ex_branch_a;
  reg                     id_ex_jump_a;
  reg  [15:0]             id_ex_pc_a;         // 8 trits = 16 bits
  reg                     id_ex_valid_a;

  // ID/EX Stage - Slot B
  reg  [TRIT_WIDTH*2-1:0] id_ex_rs1_data_b;  // 27 trits = 54 bits
  reg  [TRIT_WIDTH*2-1:0] id_ex_rs2_data_b;  // 27 trits = 54 bits
  reg  [3:0]              id_ex_rd_b;         // 2 trits = 4 bits
  reg  [3:0]              id_ex_rs1_b;        // 2 trits = 4 bits
  reg  [3:0]              id_ex_imm_b;        // 2 trits = 4 bits
  reg  [2:0]              id_ex_alu_op_b;
  reg                     id_ex_reg_write_b;
  reg                     id_ex_mem_read_b;
  reg                     id_ex_mem_write_b;
  reg                     id_ex_alu_src_b;
  reg                     id_ex_branch_b;
  reg                     id_ex_jump_b;
  reg  [15:0]             id_ex_pc_b;         // 8 trits = 16 bits
  reg                     id_ex_valid_b;

  // EX/WB Stage - Slot A
  reg  [TRIT_WIDTH*2-1:0] ex_wb_result_a;    // 27 trits = 54 bits
  reg  [TRIT_WIDTH*2-1:0] ex_wb_mem_data_a;  // 27 trits = 54 bits
  reg  [3:0]              ex_wb_rd_a;         // 2 trits = 4 bits
  reg                     ex_wb_reg_write_a;
  reg                     ex_wb_mem_read_a;
  reg                     ex_wb_valid_a;

  // EX/WB Stage - Slot B
  reg  [TRIT_WIDTH*2-1:0] ex_wb_result_b;    // 27 trits = 54 bits
  reg  [TRIT_WIDTH*2-1:0] ex_wb_mem_data_b;  // 27 trits = 54 bits
  reg  [3:0]              ex_wb_rd_b;         // 2 trits = 4 bits
  reg                     ex_wb_reg_write_b;
  reg                     ex_wb_mem_read_b;
  reg                     ex_wb_valid_b;

  // ============================================================
  // Program Counter - Dual-Issue with PC+2 Support
  // ============================================================
  reg  [15:0] pc;                    // 8 trits = 16 bits
  reg  [15:0] next_pc;               // 8 trits = 16 bits
  wire [15:0] pc_plus_one;           // 8 trits = 16 bits
  wire [15:0] pc_plus_two;           // 8 trits = 16 bits
  wire [1:0]  pc_carry_1, pc_carry_2;
  wire        pc_stall;
  reg         take_branch_a, take_branch_b;
  wire        slot_b_stall;          // Slot B stalled due to inter-slot hazard
  wire        issue_both;            // Both slots can issue this cycle

  // Local constant 1 for PC increment
  wire [15:0] const_one;
  assign const_one = {`T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_POS_ONE};

  // Local constant 2 for dual-issue PC increment (2 = 3 - 1 in balanced ternary)
  wire [15:0] const_two;
  assign const_two = {`T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_ZERO, `T_POS_ONE, `T_NEG_ONE};

  // Local constant zero for carry-in
  wire [1:0] const_zero_trit;
  assign const_zero_trit = `T_ZERO;

  // PC output for debug
  assign pc_out = pc;

  // PC increment: PC + 1
  ternary_adder #(.WIDTH(8)) pc_incrementer_1 (
    .a    (pc),
    .b    (const_one),
    .cin  (const_zero_trit),
    .sum  (pc_plus_one),
    .cout (pc_carry_1)
  );

  // PC increment: PC + 2 (for dual-issue)
  ternary_adder #(.WIDTH(8)) pc_incrementer_2 (
    .a    (pc),
    .b    (const_two),
    .cin  (const_zero_trit),
    .sum  (pc_plus_two),
    .cout (pc_carry_2)
  );

  // Branch/Jump target calculation - Slot A
  wire [15:0] branch_target_a;       // 8 trits = 16 bits
  wire [1:0]  branch_carry_a;
  wire [15:0] branch_offset_a;       // 8 trits = 16 bits

  // Sign-extend 2-trit immediate to 8 trits - Slot A
  assign branch_offset_a = {{6{id_ex_imm_a[3:2]}}, id_ex_imm_a};

  ternary_adder #(.WIDTH(8)) branch_adder_a (
    .a    (id_ex_pc_a),
    .b    (branch_offset_a),
    .cin  (const_zero_trit),
    .sum  (branch_target_a),
    .cout (branch_carry_a)
  );

  // Branch/Jump target calculation - Slot B
  wire [15:0] branch_target_b;       // 8 trits = 16 bits
  wire [1:0]  branch_carry_b;
  wire [15:0] branch_offset_b;       // 8 trits = 16 bits

  // Sign-extend 2-trit immediate to 8 trits - Slot B
  assign branch_offset_b = {{6{id_ex_imm_b[3:2]}}, id_ex_imm_b};

  ternary_adder #(.WIDTH(8)) branch_adder_b (
    .a    (id_ex_pc_b),
    .b    (branch_offset_b),
    .cin  (const_zero_trit),
    .sum  (branch_target_b),
    .cout (branch_carry_b)
  );

  // Dual-issue logic: can both slots issue?
  assign issue_both = if_id_valid_a && if_id_valid_b && !slot_b_stall;

  // Next PC selection with dual-issue awareness
  always @(*) begin
    if (take_branch_a || id_ex_jump_a) begin
      // Slot A branch/jump takes priority
      next_pc = branch_target_a;
    end else if (take_branch_b || id_ex_jump_b) begin
      // Slot B branch/jump
      next_pc = branch_target_b;
    end else if (issue_both) begin
      // Both slots issue: PC += 2
      next_pc = pc_plus_two;
    end else begin
      // Single issue or stall: PC += 1
      next_pc = pc_plus_one;
    end
  end

  // PC register
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pc <= 16'b0;
    end else if (!halted && !pc_stall) begin
      pc <= next_pc;
    end
  end

  // Instruction memory interface
  assign imem_addr = pc;

  // IPC output (instructions per cycle)
  assign ipc_out = issue_both ? 2'd2 : (if_id_valid_a ? 2'd1 : 2'd0);

  // ============================================================
  // Decoder Signals - Dual-Issue (Slot A and Slot B)
  // ============================================================

  // Slot A decoder signals
  wire [5:0] dec_opcode_a;           // 3 trits = 6 bits
  wire [3:0] dec_rd_a, dec_rs1_a, dec_rs2_imm_a;  // 2 trits = 4 bits each
  wire       dec_reg_write_a, dec_mem_read_a, dec_mem_write_a;
  wire       dec_branch_a, dec_jump_a, dec_alu_src_a;
  wire [2:0] dec_alu_op_a;
  wire       dec_halt_a;

  // Slot B decoder signals
  wire [5:0] dec_opcode_b;           // 3 trits = 6 bits
  wire [3:0] dec_rd_b, dec_rs1_b, dec_rs2_imm_b;  // 2 trits = 4 bits each
  wire       dec_reg_write_b, dec_mem_read_b, dec_mem_write_b;
  wire       dec_branch_b, dec_jump_b, dec_alu_src_b;
  wire [2:0] dec_alu_op_b;
  wire       dec_halt_b;

  // ============================================================
  // Inter-Slot Hazard Detection
  // ============================================================
  // Detect when Slot B depends on Slot A's result (same-cycle RAW hazard)
  // or when both slots want memory access (memory conflict)

  // Helper function for 2-trit address comparison
  function addr_eq_2t;
    input [3:0] a;
    input [3:0] b;
    begin
      addr_eq_2t = (a[1:0] == b[1:0]) && (a[3:2] == b[3:2]);
    end
  endfunction

  // Helper function to check if address is R0
  function is_r0_2t;
    input [3:0] addr;
    begin
      is_r0_2t = (addr[1:0] == `T_ZERO) && (addr[3:2] == `T_ZERO);
    end
  endfunction

  // Slot A writes to register that Slot B reads from Rs1
  wire slot_a_writes_slot_b_rs1;
  assign slot_a_writes_slot_b_rs1 = dec_reg_write_a &&
                                    addr_eq_2t(dec_rd_a, dec_rs1_b) &&
                                    !is_r0_2t(dec_rd_a);

  // Slot A writes to register that Slot B reads from Rs2
  wire slot_a_writes_slot_b_rs2;
  assign slot_a_writes_slot_b_rs2 = dec_reg_write_a &&
                                    !dec_alu_src_b &&  // Only if Slot B uses Rs2
                                    addr_eq_2t(dec_rd_a, dec_rs2_imm_b) &&
                                    !is_r0_2t(dec_rd_a);

  // Inter-slot RAW hazard
  wire interslot_raw_hazard;
  assign interslot_raw_hazard = (slot_a_writes_slot_b_rs1 || slot_a_writes_slot_b_rs2) &&
                                if_id_valid_a && if_id_valid_b;

  // Memory conflict: only one memory operation per cycle
  wire memory_conflict;
  assign memory_conflict = (dec_mem_read_a || dec_mem_write_a) &&
                           (dec_mem_read_b || dec_mem_write_b) &&
                           if_id_valid_a && if_id_valid_b;

  // Slot B must stall if inter-slot hazard or memory conflict
  assign slot_b_stall = interslot_raw_hazard || memory_conflict;

  // ============================================================
  // IF Stage: Instruction Fetch - Dual-Issue
  // ============================================================

  // IF/ID pipeline register - Slot A
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if_id_instr_a <= 18'b0;
      if_id_pc_a    <= 16'b0;
      if_id_valid_a <= 1'b0;
    end else if (!pc_stall) begin
      if (take_branch_a || id_ex_jump_a || take_branch_b || id_ex_jump_b) begin
        // Flush on any branch/jump
        if_id_instr_a <= 18'b0;  // NOP
        if_id_valid_a <= 1'b0;
      end else begin
        if_id_instr_a <= imem_data[17:0];   // Slot A instruction
        if_id_pc_a    <= pc;
        if_id_valid_a <= 1'b1;
      end
    end
  end

  // IF/ID pipeline register - Slot B
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      if_id_instr_b <= 18'b0;
      if_id_pc_b    <= 16'b0;
      if_id_valid_b <= 1'b0;
    end else if (!pc_stall) begin
      if (take_branch_a || id_ex_jump_a || take_branch_b || id_ex_jump_b) begin
        // Flush on any branch/jump
        if_id_instr_b <= 18'b0;  // NOP
        if_id_valid_b <= 1'b0;
      end else if (slot_b_stall) begin
        // Slot B stalled: hold instruction for next cycle
        // Actually, we need to refetch - invalidate for now
        if_id_instr_b <= 18'b0;
        if_id_valid_b <= 1'b0;
      end else begin
        if_id_instr_b <= imem_data[35:18];  // Slot B instruction
        if_id_pc_b    <= pc_plus_one;        // PC+1 for Slot B
        if_id_valid_b <= 1'b1;
      end
    end
  end

  // ============================================================
  // ID Stage: Instruction Decode - Dual-Issue
  // ============================================================

  // Slot A decoder
  btisa_decoder u_decoder_a (
    .instruction (if_id_instr_a),
    .opcode      (dec_opcode_a),
    .rd          (dec_rd_a),
    .rs1         (dec_rs1_a),
    .rs2_imm     (dec_rs2_imm_a),
    .reg_write   (dec_reg_write_a),
    .mem_read    (dec_mem_read_a),
    .mem_write   (dec_mem_write_a),
    .branch      (dec_branch_a),
    .jump        (dec_jump_a),
    .alu_src     (dec_alu_src_a),
    .alu_op      (dec_alu_op_a),
    .halt        (dec_halt_a)
  );

  // Slot B decoder
  btisa_decoder u_decoder_b (
    .instruction (if_id_instr_b),
    .opcode      (dec_opcode_b),
    .rd          (dec_rd_b),
    .rs1         (dec_rs1_b),
    .rs2_imm     (dec_rs2_imm_b),
    .reg_write   (dec_reg_write_b),
    .mem_read    (dec_mem_read_b),
    .mem_write   (dec_mem_write_b),
    .branch      (dec_branch_b),
    .jump        (dec_jump_b),
    .alu_src     (dec_alu_src_b),
    .alu_op      (dec_alu_op_b),
    .halt        (dec_halt_b)
  );

  // Register file signals - Dual-Issue
  wire [TRIT_WIDTH*2-1:0] rf_rs1_a_data, rf_rs2_a_data;
  wire [TRIT_WIDTH*2-1:0] rf_rs1_b_data, rf_rs2_b_data;
  wire [TRIT_WIDTH*2-1:0] rf_wr_data_a, rf_wr_data_b;
  wire                    rf_wr_en_a, rf_wr_en_b;

  // Register file with 4 read ports and 2 write ports
  ternary_regfile #(
    .NUM_REGS   (9),
    .TRIT_WIDTH (TRIT_WIDTH)
  ) u_regfile (
    .clk          (clk),
    .rst_n        (rst_n),
    // Slot A read ports
    .rs1_a_addr   (dec_rs1_a),
    .rs2_a_addr   (dec_rs2_imm_a),
    .rs1_a_data   (rf_rs1_a_data),
    .rs2_a_data   (rf_rs2_a_data),
    // Slot B read ports
    .rs1_b_addr   (dec_rs1_b),
    .rs2_b_addr   (dec_rs2_imm_b),
    .rs1_b_data   (rf_rs1_b_data),
    .rs2_b_data   (rf_rs2_b_data),
    // Slot A write port
    .rd_a_addr    (ex_wb_rd_a),
    .rd_a_data    (rf_wr_data_a),
    .we_a         (rf_wr_en_a),
    // Slot B write port
    .rd_b_addr    (ex_wb_rd_b),
    .rd_b_data    (rf_wr_data_b),
    .we_b         (rf_wr_en_b),
    // Debug
    .dbg_reg_idx  (dbg_reg_idx),
    .dbg_reg_data (dbg_reg_data)
  );

  // Write-back data and enable - Slot A
  assign rf_wr_data_a = ex_wb_mem_read_a ? ex_wb_mem_data_a : ex_wb_result_a;
  assign rf_wr_en_a   = ex_wb_reg_write_a && ex_wb_valid_a;

  // Write-back data and enable - Slot B
  assign rf_wr_data_b = ex_wb_mem_read_b ? ex_wb_mem_data_b : ex_wb_result_b;
  assign rf_wr_en_b   = ex_wb_reg_write_b && ex_wb_valid_b;

  // ID/EX pipeline register - Slot A
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex_rs1_data_a  <= {(TRIT_WIDTH*2){1'b0}};
      id_ex_rs2_data_a  <= {(TRIT_WIDTH*2){1'b0}};
      id_ex_rd_a        <= 4'b0;
      id_ex_rs1_a       <= 4'b0;
      id_ex_imm_a       <= 4'b0;
      id_ex_alu_op_a    <= 3'b000;
      id_ex_reg_write_a <= 1'b0;
      id_ex_mem_read_a  <= 1'b0;
      id_ex_mem_write_a <= 1'b0;
      id_ex_alu_src_a   <= 1'b0;
      id_ex_branch_a    <= 1'b0;
      id_ex_jump_a      <= 1'b0;
      id_ex_pc_a        <= 16'b0;
      id_ex_valid_a     <= 1'b0;
    end else if (pc_stall) begin
      // Insert bubble on stall
      id_ex_reg_write_a <= 1'b0;
      id_ex_mem_read_a  <= 1'b0;
      id_ex_mem_write_a <= 1'b0;
      id_ex_branch_a    <= 1'b0;
      id_ex_jump_a      <= 1'b0;
      id_ex_valid_a     <= 1'b0;
    end else begin
      id_ex_rs1_data_a  <= rf_rs1_a_data;
      id_ex_rs2_data_a  <= rf_rs2_a_data;
      id_ex_rd_a        <= dec_rd_a;
      id_ex_rs1_a       <= dec_rs1_a;
      id_ex_imm_a       <= dec_rs2_imm_a;
      id_ex_alu_op_a    <= dec_alu_op_a;
      id_ex_reg_write_a <= dec_reg_write_a;
      id_ex_mem_read_a  <= dec_mem_read_a;
      id_ex_mem_write_a <= dec_mem_write_a;
      id_ex_alu_src_a   <= dec_alu_src_a;
      id_ex_branch_a    <= dec_branch_a;
      id_ex_jump_a      <= dec_jump_a;
      id_ex_pc_a        <= if_id_pc_a;
      id_ex_valid_a     <= if_id_valid_a;
    end
  end

  // ID/EX pipeline register - Slot B
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      id_ex_rs1_data_b  <= {(TRIT_WIDTH*2){1'b0}};
      id_ex_rs2_data_b  <= {(TRIT_WIDTH*2){1'b0}};
      id_ex_rd_b        <= 4'b0;
      id_ex_rs1_b       <= 4'b0;
      id_ex_imm_b       <= 4'b0;
      id_ex_alu_op_b    <= 3'b000;
      id_ex_reg_write_b <= 1'b0;
      id_ex_mem_read_b  <= 1'b0;
      id_ex_mem_write_b <= 1'b0;
      id_ex_alu_src_b   <= 1'b0;
      id_ex_branch_b    <= 1'b0;
      id_ex_jump_b      <= 1'b0;
      id_ex_pc_b        <= 16'b0;
      id_ex_valid_b     <= 1'b0;
    end else if (pc_stall || slot_b_stall) begin
      // Insert bubble on stall
      id_ex_reg_write_b <= 1'b0;
      id_ex_mem_read_b  <= 1'b0;
      id_ex_mem_write_b <= 1'b0;
      id_ex_branch_b    <= 1'b0;
      id_ex_jump_b      <= 1'b0;
      id_ex_valid_b     <= 1'b0;
    end else begin
      id_ex_rs1_data_b  <= rf_rs1_b_data;
      id_ex_rs2_data_b  <= rf_rs2_b_data;
      id_ex_rd_b        <= dec_rd_b;
      id_ex_rs1_b       <= dec_rs1_b;
      id_ex_imm_b       <= dec_rs2_imm_b;
      id_ex_alu_op_b    <= dec_alu_op_b;
      id_ex_reg_write_b <= dec_reg_write_b;
      id_ex_mem_read_b  <= dec_mem_read_b;
      id_ex_mem_write_b <= dec_mem_write_b;
      id_ex_alu_src_b   <= dec_alu_src_b;
      id_ex_branch_b    <= dec_branch_b;
      id_ex_jump_b      <= dec_jump_b;
      id_ex_pc_b        <= if_id_pc_b;
      id_ex_valid_b     <= if_id_valid_b;
    end
  end

  // ============================================================
  // EX Stage: Execute - Dual-Issue with Two ALUs
  // ============================================================

  // Slot A ALU signals
  reg  [TRIT_WIDTH*2-1:0] alu_a_op1, alu_a_op2;
  wire [TRIT_WIDTH*2-1:0] alu_result_a;
  wire [1:0]              alu_carry_a;
  wire                    alu_neg_a;
  wire                    alu_zero_a;

  // Slot B ALU signals
  reg  [TRIT_WIDTH*2-1:0] alu_b_op1, alu_b_op2;
  wire [TRIT_WIDTH*2-1:0] alu_result_b;
  wire [1:0]              alu_carry_b;
  wire                    alu_neg_b;
  wire                    alu_zero_b;

  // Forwarded data from MEM/WB stage (simplified - use Slot A result for now)
  wire [TRIT_WIDTH*2-1:0] mem_forward_data_a;
  assign mem_forward_data_a = ex_wb_mem_read_a ? ex_wb_mem_data_a : ex_wb_result_a;

  // Sign-extension for immediate - Slot A (MSB trit)
  wire [1:0] imm_sign_trit_a;
  assign imm_sign_trit_a = id_ex_imm_a[3:2];

  // Sign-extension for immediate - Slot B (MSB trit)
  wire [1:0] imm_sign_trit_b;
  assign imm_sign_trit_b = id_ex_imm_b[3:2];

  // Forwarding control signals (simplified for now - will use dual hazard unit later)
  wire [1:0] forward_a_rs1, forward_a_rs2;
  wire [1:0] forward_b_rs1, forward_b_rs2;

  // Slot A ALU input A with forwarding
  always @(*) begin
    case (forward_a_rs1)
      2'b01:   alu_a_op1 = mem_forward_data_a;
      2'b10:   alu_a_op1 = mem_forward_data_a;
      default: alu_a_op1 = id_ex_rs1_data_a;
    endcase
  end

  // Slot A ALU input B with forwarding
  always @(*) begin
    if (id_ex_alu_src_a) begin
      alu_a_op2 = {{(TRIT_WIDTH-2){imm_sign_trit_a}}, id_ex_imm_a};
    end else begin
      case (forward_a_rs2)
        2'b01:   alu_a_op2 = mem_forward_data_a;
        2'b10:   alu_a_op2 = mem_forward_data_a;
        default: alu_a_op2 = id_ex_rs2_data_a;
      endcase
    end
  end

  // Slot B ALU input A with forwarding
  always @(*) begin
    case (forward_b_rs1)
      2'b01:   alu_b_op1 = mem_forward_data_a;
      2'b10:   alu_b_op1 = mem_forward_data_a;
      default: alu_b_op1 = id_ex_rs1_data_b;
    endcase
  end

  // Slot B ALU input B with forwarding
  always @(*) begin
    if (id_ex_alu_src_b) begin
      alu_b_op2 = {{(TRIT_WIDTH-2){imm_sign_trit_b}}, id_ex_imm_b};
    end else begin
      case (forward_b_rs2)
        2'b01:   alu_b_op2 = mem_forward_data_a;
        2'b10:   alu_b_op2 = mem_forward_data_a;
        default: alu_b_op2 = id_ex_rs2_data_b;
      endcase
    end
  end

  // Slot A ALU instance
  ternary_alu #(.WIDTH(TRIT_WIDTH)) u_alu_a (
    .a         (alu_a_op1),
    .b         (alu_a_op2),
    .op        (id_ex_alu_op_a),
    .result    (alu_result_a),
    .carry     (alu_carry_a),
    .zero_flag (alu_zero_a),
    .neg_flag  (alu_neg_a)
  );

  // Slot B ALU instance
  ternary_alu #(.WIDTH(TRIT_WIDTH)) u_alu_b (
    .a         (alu_b_op1),
    .b         (alu_b_op2),
    .op        (id_ex_alu_op_b),
    .result    (alu_result_b),
    .carry     (alu_carry_b),
    .zero_flag (alu_zero_b),
    .neg_flag  (alu_neg_b)
  );

  // Branch condition evaluation - Slot A
  always @(*) begin
    take_branch_a = 1'b0;
    if (id_ex_branch_a && id_ex_valid_a) begin
      case (id_ex_alu_op_a)
        3'b001: take_branch_a = alu_zero_a;  // BEQ
        default: take_branch_a = 1'b0;
      endcase
    end
  end

  // Branch condition evaluation - Slot B
  always @(*) begin
    take_branch_b = 1'b0;
    if (id_ex_branch_b && id_ex_valid_b) begin
      case (id_ex_alu_op_b)
        3'b001: take_branch_b = alu_zero_b;  // BEQ
        default: take_branch_b = 1'b0;
      endcase
    end
  end

  // Data memory interface - Slot A has priority
  assign dmem_addr  = (id_ex_mem_read_a || id_ex_mem_write_a) ? alu_result_a[17:0] : alu_result_b[17:0];
  assign dmem_wdata = id_ex_mem_write_a ? id_ex_rs2_data_a : id_ex_rs2_data_b;
  assign dmem_we    = (id_ex_mem_write_a && id_ex_valid_a) ||
                      (id_ex_mem_write_b && id_ex_valid_b && !id_ex_mem_write_a);
  assign dmem_re    = (id_ex_mem_read_a && id_ex_valid_a) ||
                      (id_ex_mem_read_b && id_ex_valid_b && !id_ex_mem_read_a);

  // Track which slot performed memory operation
  reg mem_op_was_slot_a;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      mem_op_was_slot_a <= 1'b0;
    else
      mem_op_was_slot_a <= id_ex_mem_read_a || id_ex_mem_write_a;
  end

  // EX/WB pipeline register - Slot A
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_wb_result_a    <= {(TRIT_WIDTH*2){1'b0}};
      ex_wb_mem_data_a  <= {(TRIT_WIDTH*2){1'b0}};
      ex_wb_rd_a        <= 4'b0;
      ex_wb_reg_write_a <= 1'b0;
      ex_wb_mem_read_a  <= 1'b0;
      ex_wb_valid_a     <= 1'b0;
    end else begin
      ex_wb_result_a    <= alu_result_a;
      ex_wb_mem_data_a  <= (id_ex_mem_read_a && id_ex_valid_a) ? dmem_rdata : {(TRIT_WIDTH*2){1'b0}};
      ex_wb_rd_a        <= id_ex_rd_a;
      ex_wb_reg_write_a <= id_ex_reg_write_a;
      ex_wb_mem_read_a  <= id_ex_mem_read_a;
      ex_wb_valid_a     <= id_ex_valid_a;
    end
  end

  // EX/WB pipeline register - Slot B
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ex_wb_result_b    <= {(TRIT_WIDTH*2){1'b0}};
      ex_wb_mem_data_b  <= {(TRIT_WIDTH*2){1'b0}};
      ex_wb_rd_b        <= 4'b0;
      ex_wb_reg_write_b <= 1'b0;
      ex_wb_mem_read_b  <= 1'b0;
      ex_wb_valid_b     <= 1'b0;
    end else begin
      ex_wb_result_b    <= alu_result_b;
      ex_wb_mem_data_b  <= (id_ex_mem_read_b && id_ex_valid_b && !id_ex_mem_read_a) ? dmem_rdata : {(TRIT_WIDTH*2){1'b0}};
      ex_wb_rd_b        <= id_ex_rd_b;
      ex_wb_reg_write_b <= id_ex_reg_write_b;
      ex_wb_mem_read_b  <= id_ex_mem_read_b;
      ex_wb_valid_b     <= id_ex_valid_b;
    end
  end

  // ============================================================
  // Control / Hazard Detection and Forwarding - Dual-Issue
  // ============================================================

  wire        if_id_stall_a, if_id_stall_b;
  wire        id_ex_flush_a, id_ex_flush_b;

  // Convert 2-trit addresses to 3-trit for hazard/forward units (pad with zero trit)
  wire [5:0] dec_rs1_a_3t, dec_rs2_a_3t, id_ex_rd_a_3t, ex_wb_rd_a_3t;
  wire [5:0] dec_rs1_b_3t, dec_rs2_b_3t, id_ex_rd_b_3t, ex_wb_rd_b_3t;

  assign dec_rs1_a_3t  = {`T_ZERO, dec_rs1_a};
  assign dec_rs2_a_3t  = {`T_ZERO, dec_rs2_imm_a};
  assign id_ex_rd_a_3t = {`T_ZERO, id_ex_rd_a};
  assign ex_wb_rd_a_3t = {`T_ZERO, ex_wb_rd_a};

  assign dec_rs1_b_3t  = {`T_ZERO, dec_rs1_b};
  assign dec_rs2_b_3t  = {`T_ZERO, dec_rs2_imm_b};
  assign id_ex_rd_b_3t = {`T_ZERO, id_ex_rd_b};
  assign ex_wb_rd_b_3t = {`T_ZERO, ex_wb_rd_b};

  // Hazard Detection Unit - Slot A (use existing unit for now)
  ternary_hazard_unit u_hazard_unit_a (
    .id_rs1       (dec_rs1_a_3t),
    .id_rs2       (dec_rs2_a_3t),
    .id_uses_rs1  (1'b1),
    .id_uses_rs2  (!dec_alu_src_a),
    .ex_rd        (id_ex_rd_a_3t),
    .ex_reg_write (id_ex_reg_write_a),
    .ex_mem_read  (id_ex_mem_read_a),
    .mem_rd       (ex_wb_rd_a_3t),
    .mem_reg_write(ex_wb_reg_write_a),
    .pc_stall     (pc_stall),
    .if_id_stall  (if_id_stall_a),
    .id_ex_flush  (id_ex_flush_a)
  );

  // Simplified forwarding for Slot A
  wire [5:0] id_ex_rs1_a_3t, id_ex_rs2_a_3t;
  assign id_ex_rs1_a_3t = {`T_ZERO, id_ex_rs1_a};
  assign id_ex_rs2_a_3t = {`T_ZERO, id_ex_imm_a};

  ternary_forward_unit u_forward_unit_a (
    .ex_rs1       (id_ex_rs1_a_3t),
    .ex_rs2       (id_ex_rs2_a_3t),
    .mem_rd       (ex_wb_rd_a_3t),
    .mem_reg_write(ex_wb_reg_write_a),
    .wb_rd        (ex_wb_rd_a_3t),
    .wb_reg_write (ex_wb_reg_write_a),
    // Outputs
    .forward_a    (forward_a_rs1),
    .forward_b    (forward_a_rs2)
  );

  // Simplified forwarding for Slot B (use same signals for now)
  wire [5:0] id_ex_rs1_b_3t, id_ex_rs2_b_3t;
  assign id_ex_rs1_b_3t = {`T_ZERO, id_ex_rs1_b};
  assign id_ex_rs2_b_3t = {`T_ZERO, id_ex_imm_b};

  ternary_forward_unit u_forward_unit_b (
    .ex_rs1       (id_ex_rs1_b_3t),
    .ex_rs2       (id_ex_rs2_b_3t),
    .mem_rd       (ex_wb_rd_a_3t),
    .mem_reg_write(ex_wb_reg_write_a),
    .wb_rd        (ex_wb_rd_a_3t),
    .wb_reg_write (ex_wb_reg_write_a),
    // Outputs
    .forward_a    (forward_b_rs1),
    .forward_b    (forward_b_rs2)
  );

  assign stall_out = pc_stall;
  assign fwd_a_out = (forward_a_rs1 != 2'b00) || (forward_a_rs2 != 2'b00);
  assign fwd_b_out = (forward_b_rs1 != 2'b00) || (forward_b_rs2 != 2'b00);

  // Valid outputs - Dual-Issue
  assign valid_out_a = ex_wb_valid_a;
  assign valid_out_b = ex_wb_valid_b;

  // ============================================================
  // Halt Detection - Dual-Issue
  // ============================================================

  // Halt flag register (halt from either slot)
  reg halt_reg;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      halt_reg <= 1'b0;
    end else if ((dec_halt_a && if_id_valid_a) || (dec_halt_b && if_id_valid_b)) begin
      halt_reg <= 1'b1;
    end
  end

  assign halted = halt_reg;

endmodule

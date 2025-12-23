# Balanced Ternary Instruction Set Architecture (BTISA) v0.1

## Overview
- **Word size**: 27 trits (≈42.8 bits equivalent)
- **Register count**: 9 general-purpose (R0-R8)
- **Memory**: Trit-addressable, initial 729 words (3^6)
- **Encoding**: All instructions are 9 trits

## Balanced Ternary Notation
In this ISA, we use the following notation:
- `-` represents -1 (T_NEG_ONE)
- `0` represents 0 (T_ZERO)
- `+` represents +1 (T_POS_ONE)

## Register Set
| Register | Alias | Description |
|----------|-------|-------------|
| R0 | zero | Always zero (hardwired) |
| R1 | t1 | General purpose |
| R2 | t2 | General purpose |
| R3 | t3 | General purpose |
| R4 | t4 | General purpose |
| R5 | t5 | General purpose |
| R6 | t6 | General purpose |
| R7 | t7 | General purpose |
| R8 | ra | Return address |

### Register Encoding (2 trits)
| Register | Encoding | Decimal |
|----------|----------|---------|
| R0 | 00 | 0 |
| R1 | 0+ | 1 |
| R2 | 0- | 2 |
| R3 | +0 | 3 |
| R4 | ++ | 4 |
| R5 | +- | 5 |
| R6 | -0 | 6 |
| R7 | -+ | 7 |
| R8 | -- | 8 |

## Instruction Encoding (9 trits)
```
[8:6] Opcode  (3 trits = 27 opcodes possible)
[5:4] Rd      (2 trits = 9 registers)
[3:2] Rs1     (2 trits = 9 registers)
[1:0] Rs2/Imm (2 trits = 9 values or register)
```

## Instruction Set

### Arithmetic Operations (Opcode 0XX)
| Opcode | Mnemonic | Operation | Description |
|--------|----------|-----------|-------------|
| 000 | ADD | Rd = Rs1 + Rs2 | Ternary addition |
| 00+ | SUB | Rd = Rs1 - Rs2 | Ternary subtraction |
| 00- | NEG | Rd = -Rs1 | Negate (flip all trits) |
| 0+0 | MUL | Rd = Rs1 × Rs2 | Ternary multiply (future) |
| 0++ | SHL | Rd = Rs1 << 1 | Shift left (×3) |
| 0+- | SHR | Rd = Rs1 >> 1 | Shift right (÷3) |
| 0-0 | ADDI | Rd = Rs1 + Imm | Add immediate |

### Logic Operations (Opcode +XX)
| Opcode | Mnemonic | Operation | Description |
|--------|----------|-----------|-------------|
| +00 | MIN | Rd = MIN(Rs1, Rs2) | Tritwise minimum (AND) |
| +0+ | MAX | Rd = MAX(Rs1, Rs2) | Tritwise maximum (OR) |
| +0- | XOR | Rd = Rs1 XOR Rs2 | Ternary XOR (mod-3 add) |
| ++0 | INV | Rd = STI(Rs1) | Standard ternary invert |
| +++ | PTI | Rd = PTI(Rs1) | Positive threshold invert |
| ++- | NTI | Rd = NTI(Rs1) | Negative threshold invert |

### Memory Operations (Opcode -XX)
| Opcode | Mnemonic | Operation | Description |
|--------|----------|-----------|-------------|
| -00 | LD | Rd = Mem[Rs1 + Imm] | Load word |
| -0+ | ST | Mem[Rs1 + Imm] = Rs2 | Store word |
| -0- | LDT | Rd = Mem[Rs1][Imm] | Load single trit |
| -+0 | STT | Mem[Rs1][Imm] = Rs2[0] | Store single trit |
| -++ | LUI | Rd = Imm << 18 | Load upper immediate |

### Control Flow (Opcode 0-X and +-X)
| Opcode | Mnemonic | Operation | Description |
|--------|----------|-----------|-------------|
| 0-0 | BEQ | if Rs1=Rs2: PC += Imm | Branch if equal |
| 0-+ | BNE | if Rs1≠Rs2: PC += Imm | Branch if not equal |
| 0-- | BLT | if Rs1<Rs2: PC += Imm | Branch if less than |
| +-0 | JAL | Rd = PC+1; PC = Rs1+Imm | Jump and link |
| +-+ | JALR | Rd = PC+1; PC = Rs1 | Jump and link register |
| +-- | JR | PC = Rs1 | Jump register (ret) |

### System Operations (Opcode --X)
| Opcode | Mnemonic | Operation | Description |
|--------|----------|-----------|-------------|
| --0 | NOP | - | No operation |
| --+ | HALT | - | Halt execution |
| --- | ECALL | - | Environment call |

## Opcode Encoding Summary
| Opcode [8:6] | Category |
|--------------|----------|
| 000 | ADD |
| 00+ | SUB |
| 00- | NEG |
| 0+0 | MUL |
| 0++ | SHL |
| 0+- | SHR |
| 0-0 | BEQ |
| 0-+ | BNE |
| 0-- | BLT |
| +00 | MIN |
| +0+ | MAX |
| +0- | XOR |
| ++0 | INV |
| +++ | PTI |
| ++- | NTI |
| +-0 | JAL |
| +-+ | JALR |
| +-- | JR |
| -00 | LD |
| -0+ | ST |
| -0- | LDT |
| -+0 | STT |
| -++ | LUI |
| --0 | NOP |
| --+ | HALT |
| --- | ECALL |

## ALU Operation Codes (3 bits binary)
| ALU Op | Operation |
|--------|-----------|
| 000 | ADD |
| 001 | SUB |
| 010 | NEG |
| 011 | MIN |
| 100 | MAX |
| 101 | SHL |
| 110 | SHR |
| 111 | CMP |

## Condition Codes / Flags
| Flag | Description |
|------|-------------|
| Z | Zero flag: result is all zeros |
| N | Negative flag: MSB trit is -1 |
| C | Carry flag: overflow/underflow in addition |

## Example Assembly Programs

### Example 1: Compute Fibonacci(5)
```asm
# R1 = n, R2 = fib(n-1), R3 = fib(n-2), R4 = result

    ADDI R1, R0, 5    # n = 5
    ADDI R2, R0, 1    # fib(1) = 1
    ADD  R3, R0, R0   # fib(0) = 0

loop:
    BEQ  R1, R0, done # if n == 0, exit
    ADD  R4, R2, R3   # result = fib(n-1) + fib(n-2)
    ADD  R3, R2, R0   # fib(n-2) = fib(n-1)
    ADD  R2, R4, R0   # fib(n-1) = result
    SUB  R1, R1, 1    # n = n - 1
    BNE  R0, R1, loop # continue loop

done:
    HALT
```

### Example 2: Memory Copy
```asm
# Copy 3 words from address in R1 to address in R2
# R3 = counter, R4 = temp

    ADDI R3, R0, 3    # counter = 3

copy_loop:
    BEQ  R3, R0, done # if counter == 0, done
    LD   R4, R1, 0    # load from source
    ST   R4, R2, 0    # store to destination
    ADDI R1, R1, 1    # source++
    ADDI R2, R2, 1    # dest++
    SUB  R3, R3, 1    # counter--
    BNE  R0, R3, copy_loop

done:
    HALT
```

## Memory Map
| Address Range | Description |
|---------------|-------------|
| 0x000 - 0x0FF | Instruction memory (243 words) |
| 0x100 - 0x2FF | Data memory (486 words) |
| 0x300 - 0x3FF | I/O mapped peripherals |

## Pipeline Stages
The BTISA CPU uses a 4-stage pipeline:
1. **IF** - Instruction Fetch
2. **ID** - Instruction Decode / Register Read
3. **EX** - Execute / Memory Address Calculation
4. **WB** - Write Back

## Notes
- R0 is hardwired to zero; writes to R0 are ignored
- Balanced ternary negation is trivial: just flip all trits
- No need for two's complement - balanced ternary is symmetric
- Immediate values use sign extension from 2 trits to 27 trits

---
**Version**: 0.1
**Date**: 2025-12-17
**Status**: Initial specification for CPU implementation

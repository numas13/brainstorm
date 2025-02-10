#include "common.h"

    .text
    .global FUNCTION_NAME
    .type FUNCTION_NAME, function
FUNCTION_NAME:
    addi    sp,sp,-64
    sd      s5,8(sp)
    sd      s4,16(sp)
    sd      s3,24(sp)
    sd      s2,32(sp)
    sd      s1,40(sp)
    sd      s0,48(sp)
    sd      ra,56(sp)
    mv      s0,a0               // code
    mv      s1,a1               // code_size
    mv      s2,a2               // tape_base
    mv      s3,a3               // tape_size
    li      s4,0                // pc
    li      s5,0                // i
    j       .L_loop

.L_out_of_bounds:
    li      a0,1
    j       1f

.L_exit:
    li      a0,0
1:
    ld      s5,8(sp)
    ld      s4,16(sp)
    ld      s3,24(sp)
    ld      s2,32(sp)
    ld      s1,40(sp)
    ld      s0,48(sp)
    ld      ra,56(sp)
    addi    sp,sp,64
    ret

.L_loop:
    bgeu    s4,s1,.L_exit       // is pc out of bounds?

#if DUMP_STATE
    mv      a0,s0               // code
    mv      a1,s1               // code_size
    mv      a2,s2               // tape_base
    mv      a3,s3               // tape_size
    mv      a4,s4               // pc
    mv      a5,s5               // i
    call    bf_dump_state
#endif

    add     t0,s0,s4            // insn pointer
    lh      t1,0(t0)            // load insn.opcode_and_target
    lbu     t2,2(t0)            // load insn.add
    lb      t3,3(t0)            // load insn.mov

    add     s5,s5,t3            // move cursor
    bgeu    s5,s3,.L_out_of_bounds // is i out of bounds?

    add     t0,s2,s5            // address of tape[i]
    lb      a0,0(t0)            // tape[i]
    add     a0,a0,t2            // tape[i] + insn.add
    sb      a0,0(t0)            // store updated tape[i]

    addi    s4,s4,4             // set pc to next insn
    beqz    t1,.L_loop          // no branch or call
    andi    a0,a0,0xff
    bgt     t1,zero,0f          // is target greater then zero?

.L_bnez:
    beqz    a0,.L_loop          // branch is not taken
    add     s4,s4,t1            // branch to target pc
    j       .L_loop

0:
    andi    t0,t1,1             // is OPCODE_CALL?
    bnez    t0,.L_call

.L_beqz:
    bnez    a0,.L_loop          // branch is not taken
    add     s4,s4,t1            // branch to target pc
    j       .L_loop

.L_call:
    li      t0,3
    beq     t1,t0,0f
    call    bf_putc
    j       .L_loop
0:
    call    bf_getc
    add     t0,s2,s5            // address of tape[i]
    sb      a0,0(t0)            // override cell
    j       .L_loop

    .size FUNCTION_NAME, . - FUNCTION_NAME

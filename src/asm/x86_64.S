#include "common.h"

    .text
    .global FUNCTION_NAME
    .type FUNCTION_NAME, function
FUNCTION_NAME:
    push    %rbp
    mov     %rsp,%rbp
    push    %rbx
    push    %r12
    push    %r13
    push    %r14
    push    %r15
    mov     %rdi,%rbx           // code
    mov     %rsi,%r12           // code_size
    mov     %rdx,%r13           // tape_base
    mov     %rcx,%r14           // tape_size
    xor     %rcx,%rcx           // pc
    xor     %r15,%r15           // i
    jmp     .L_loop

.L_exit:
    pop     %r15
    pop     %r14
    pop     %r13
    pop     %r12
    pop     %rbx
    pop     %rbp
    ret

    .balign 32
.L_loop:
    cmp     %r12,%rcx           // is pc out of bounds?
    jae     .L_exit

#if DUMP_STATE
    push    %rcx                // save pc
    mov     %rcx,%r8            // pc
    mov     %r15,%r9            // i
    mov     %rbx,%rdi           // code
    mov     %r12,%rsi           // code_size
    mov     %r13,%rdx           // tape_base
    mov     %r14,%rcx           // tape_size
    call    bf_dump_state
    pop     %rcx                // restore pc
#endif

    movsw   (%rbx,%rcx),%rsi    // load insn.opcode_and_target
    movzb   2(%rbx,%rcx),%edi   // load insn.add
    movsb   3(%rbx,%rcx),%rax   // load insn.mov

    add     %rax,%r15           // move cursor
    cmp     %r14,%r15           // is i out of bounds?
    jae     .L_out_of_bounds

    add     (%r13,%r15),%dil    // tape[i] + insn.add
    mov     %dil,(%r13,%r15)    // store updated tape[i]

    add     $4,%rcx             // set pc to next insn

    test    %rsi,%rsi
    jz      .L_loop             // no branch or call

    test    %rsi,%rsi           // is target greater then zero?
    jg      0f                  // not a bnez

.L_bnez:
    test    %dil,%dil           // is cell zero?
    jz      .L_loop             // branch is not taken
    add     %rsi,%rcx           // branch to target pc
    prefetcht0 (%rbx,%rcx)      // prefetch branch target
    jmp     .L_loop

    .balign 32
0:
    test    $1,%rsi             // is OPCODE_CALL?
    jnz     .L_call

.L_beqz:
    test    %dil,%dil           // is cell zero?
    jnz     .L_loop             // branch is not taken
    add     %rsi,%rcx           // branch to target pc
    prefetcht0 (%rbx,%rcx)      // prefetch branch target
    jmp     .L_loop

    .balign 32
.L_call:
    cmp     $3,%rsi             // is TARGET_PUTC?
    je      0f
    push    %rcx                // save pc
    movzb   %dil,%edi           // zero extend cell value
    call    bf_putc
    pop     %rcx                // restore pc
    jmp     .L_loop
0:
    push    %rcx                // save pc
    call    bf_getc
    pop     %rcx                // restore pc
    mov     %al,(%r13,%r15)     // override cell
    jmp     .L_loop

.L_out_of_bounds:
    ud2                         // out of bounds

    .size FUNCTION_NAME, . - FUNCTION_NAME

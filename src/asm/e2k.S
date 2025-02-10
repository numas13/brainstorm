#include "common.h"

#define wasted_cycles nop

#define WSZ 20
#define RSZ 11
#define RBS 8
#define PSZ 16

#define FIELD_OPCODE ( 0 | ( 2 << 6))
#define FIELD_TARGET ( 0 | (16 << 6) | (1 << 12) | (1 << 13))
#define FIELD_ADDEND (16 | ( 8 << 6) | (1 << 12) | (2 << 13))
#define FIELD_CURMOV (24 | ( 8 << 6) | (1 << 12) | (3 << 13))

#define CODE                %r0
#define CODE_LEN            %r1
#define TAPE                %r2
#define TAPE_LEN            %r3
#define PC                  %r4
#define I                   %r5

// Pipeline stages::
// P - next pc
// F - fetch insn
// D - decode insn
// R - read tape[i]
// E - add value, store result, branch/call

#define PC_P                %b[0]
#define PC_F                %b[2]
#define PC_D                %b[4]
#define PC_R                %b[6]
#define PC_E                %b[8]
#define ADD_D               %b[10]
#define ADD_R               %b[12]
#define ADD_E               %b[14]
#define TARGET_D            %b[16]
#define TARGET_R            %b[18]
#define TARGET_E            %b[20]

#define INSN_F              %b[1]
#define INSN_D              %b[3]
#define INSN_R              %b[5]
#define INSN_E              %b[7]
#define I_D                 %b[9]
#define I_R                 %b[11]
#define I_E                 %b[13]
#define I_W                 %b[15]
#define CELL_R              %b[17]
#define CELL_E              %b[19]
#define CELL_W              %b[21]

#define MOV_D               %g16
#define MOV_R               %g17
#define MOV_E               %g18
#define IS_EXE_D            %pred0
#define IS_EXE_R            %pred1
#define IS_EXE_E            %pred2
#define IS_NOT_CALL_D       %pred3
#define IS_NOT_CALL_R       %pred4
#define IS_NOT_CALL_E       %pred5
#define IS_NOT_EXIT_F       %pred6
#define IS_NOT_EXIT_D       %pred7
#define IS_NOT_EXIT_R       %pred8
#define IS_NOT_EXIT_E       %pred9
#define IS_BYPASS_R         %pred10
#define IS_BYPASS_E         %pred11
#define IS_BOUNDS_R         %pred12
#define IS_BOUNDS_E         %pred13
#define IS_BNEZ_R           %pred14
#define IS_BNEZ_E           %pred15
#define IS_TAKEN_E          %pred16

    .macro dump_state
#if DUMP_STATE
    // numas13: I hate prepared control flow and calling convention in E2K :)
    {
        addd,0          CODE,0,%g31
        addd,1          CODE_LEN,0,%g30
        addd,2          TAPE,0,%g29
        addd,3          TAPE_LEN,0,%g28
        addd,4          PC_E,0,%g27
        addd,5          I_W,0,%g26
        disp            %ctpr1,0f
        wasted_cycles 4
    }
        // this call is needed to save pipeline state...
        call            %ctpr1,wbs=WSZ
        disp            %ctpr1,loop
        disp            %ctpr2,call
        disp            %ctpr3,pipeline
        ibranch         1f
0:
    {
        setwd           wsz=8,nfx=1,dbl=1
        setbn           rsz=3,rbs=4,rcur=0
        disp            %ctpr1,bf_dump_state
        wasted_cycles 4
    }
    {
        addd,0          %g31,0,%b[0]
        addd,1          %g30,0,%b[1]
        addd,2          %g29,0,%b[2]
        addd,3          %g28,0,%b[3]
        addd,4          %g27,0,%b[4]
        addd,5          %g26,0,%b[5]
        call            %ctpr1,wbs=4
    }
    {
        return          %ctpr3
        wasted_cycles 5
    }
        ct              %ctpr3
1:
#endif
    .endm // dump_state

    .text
    .global FUNCTION_NAME
    .balign 8
FUNCTION_NAME:
    {
        setwd           wsz=WSZ,nfx=1,dbl=1
        setbn           rsz=RSZ,rbs=RBS,rcur=0
        setbp           psz=PSZ
        addd,0          0,0,PC
        addd,1          0,0,I
        disp            %ctpr3,pipeline
    }
    {
        addd,0          PC,0,PC_E
        addd,1          I,0,I_W
        ldw,2,sm        CODE,PC,INSN_E                  // insn = code[pc]
        disp            %ctpr1,loop
    }
    {
        addd,2          PC,8,PC_D                       // set pc to next insn
        addd,3          PC,4,PC_R                       // set pc to next insn
        addd,4          PC,12,PC_F                      // set pc to next insn
        disp            %ctpr2,call
    }
        ct              %ctpr3

call:
    {
        setwd           wsz=8,nfx=1,dbl=1
        setbn           rsz=3,rbs=4,rcur=0
        cmpedb,0        %g16,1,%pred31                  // is FUNC_PUTC?
        cmpedb,1        %g16,3,%pred30                  // is FUNC_GETC?
        disp            %ctpr1,bf_putc
    }
    {
        disp            %ctpr2,bf_getc

        pass            %pred31,@p0                     // is FUNC_PUTC?
        pass            %pred30,@p1                     // is FUNC_GETC?
        andp            ~@p0,~@p1,@p4
        pass            @p4,%pred29                     // is invalid func?

        wasted_cycles   2
    }
        ldb,5           0,0,%empty ? %pred29            // invalid func
    {
        addd,0          %g17,0,%b[0] ? %pred31          // bf_putc(tape[i])
        call            %ctpr1,wbs=4 ? %pred31          // bf_putc(tape[i])
    }
        call            %ctpr2,wbs=4 ? %pred30          // %b[0] = bf_getc()
    {
        setwd           wsz=WSZ,nfx=1,dbl=1
        setbn           rsz=RSZ,rbs=RBS,rcur=0
        setbp           psz=PSZ
        stb,2           %b[0],[TAPE + I] ? %pred30      // tape[i]=%b[0]
        disp            %ctpr1,loop
    }
    {
        addd,0          PC,0,PC_E
        addd,1          I,0,I_W
        ldw,2,sm        CODE,PC,INSN_E                  // insn = code[pc]
        disp            %ctpr2,call
    }
    {
        addd,2          PC,8,PC_D                       // set pc to next insn
        addd,3          PC,4,PC_R                       // set pc to next insn
        addd,4          PC,12,PC_F                      // set pc to next insn
        disp            %ctpr3,pipeline
    }
pipeline:
    {
        ldw,2,sm        CODE,PC_D,INSN_D                // insn = code[pc]
        ldw,5,sm        CODE,PC_R,INSN_R                // insn = code[pc]
    }
    {
        sxt,0,sm        1,INSN_E,TARGET_E               // extract insn.target
        getfd,1,sm      INSN_E,FIELD_CURMOV,MOV_E       // extract insn.mov
        getfd,2,sm      INSN_E,FIELD_ADDEND,ADD_E       // extract insn.add
    }
    {
        cmpbdb,0        PC_E,CODE_LEN,IS_NOT_EXIT_E     // is pc out of bounds?
        cmpbdb,1        PC_D,CODE_LEN,IS_NOT_EXIT_D     // is pc out of bounds?
        cmpbdb,3        PC_R,CODE_LEN,IS_NOT_EXIT_R     // is pc out of bounds?
        cmpedb,4        0,1,IS_BYPASS_E                 // need bypass? (no)
        addd,2,sm       I_W,MOV_E,I_E                   // move cursor
    }
    {
        ldb,2,sm        TAPE,I_E,CELL_E                 // load tape[i]
    }
    {
        cmpedb,0,sm     TARGET_E,0,IS_EXE_E             // do not have call or br?
        cmpandedb,1,sm  TARGET_E,1,IS_NOT_CALL_E        // is call?
    }
    {
        cmpldb,0,sm     TARGET_E,0,IS_BNEZ_E            // is bnez?
        cmpbdb,1,sm     I_E,TAPE_LEN,IS_BOUNDS_E        // is i out of bounds?
        sxt,3,sm        1,INSN_R,TARGET_R               // extract insn.target
        getfd,4,sm      INSN_R,FIELD_CURMOV,MOV_R       // extract insn.mov
        getfd,5,sm      INSN_R,FIELD_ADDEND,ADD_R       // extract insn.add
    }
    {
        cmpedb,3,sm     TARGET_R,0,IS_EXE_R             // do not have call or br?
        cmpandedb,4,sm  TARGET_R,1,IS_NOT_CALL_R        // is call?
        addd,5,sm       I_E,MOV_R,I_R                   // move cursor
    }

loop:
    {
        ldw,0,sm        CODE,PC_F,INSN_F                // insn = code[pc]

        getfd,1,sm      INSN_D,FIELD_CURMOV,MOV_D       // extract insn.mov
        sxt,2,sm        1,INSN_D,TARGET_D               // extract insn.target

        ldb,3,sm        TAPE,I_R,CELL_R                 // load tape[i]

        addd,4,sm       CELL_E,ADD_E,CELL_E ? ~IS_BYPASS_E  // tape[i] + insn.add
        addd,5,sm       CELL_W,ADD_E,CELL_E ? IS_BYPASS_E   // tape[i] + insn.add (bypass)
        ibranch         exit ? ~IS_NOT_EXIT_E
    }
        dump_state
    {
        cmpedb,0,sm     TARGET_D,0,IS_EXE_D             // do not have call or br?
        getfd,2,sm      INSN_D,FIELD_ADDEND,ADD_D       // extract insn.add

        cmpbdb,1,sm     I_R,TAPE_LEN,IS_BOUNDS_R        // is i out of bounds?
        cmpedb,4,sm     I_R,I_E,IS_BYPASS_R             // need bypass?

        cmpandedb,3     CELL_E,0xff,IS_TAKEN_E          // is cell zero?
        stb,5           CELL_E,[TAPE + I_E] ? IS_BOUNDS_E // store updated tape[i]
        ibranch         out_of_bounds ? ~IS_BOUNDS_E    // i is out of bounds
    }
    {
        addd,2          PC_F,4,PC_P                     // set pc to next insn
        cmpbdb,4        PC_F,CODE_LEN,IS_NOT_EXIT_F     // is pc out of bounds?

        cmpandedb,0,sm  TARGET_D,1,IS_NOT_CALL_D        // is call?
        addd,3,sm       I_R,MOV_D,I_D                   // move cursor

        cmpldb,1,sm     TARGET_R,0,IS_BNEZ_R            // is bnez?

        pass            IS_TAKEN_E,@p0                  // is cell zero?
        pass            IS_BNEZ_E,@p1                   // is bnez?
        movep           @p1,~@p0,@p4
        pass            @p4,IS_TAKEN_E                  // is branch taken?

        abn             abnf=0,abnt=1
        abp             abpf=0,abpt=1
        ct              %ctpr1 ? IS_EXE_E               // loop
    }

    // execute call/branch with pipeline restart
    {
        addd,0          PC_E,4,PC
        addd,1          I_E,0,I                         // save i
        addd,2          TARGET_E,0,%g16
        sxt,3           4,CELL_E,%g17                   // zero-extend cell value

        ct              %ctpr2 ? ~IS_NOT_CALL_E         // execute call
    }
    {
        addd,0          PC,TARGET_E,PC ? IS_TAKEN_E     // branch is taken, set pc to branch target
    }
    {
        addd,0          PC,0,PC_E ? IS_TAKEN_E
        addd,1          I,0,I_W ? IS_TAKEN_E
        ldw,2,sm        CODE,PC,INSN_E ? IS_TAKEN_E     // insn = code[pc]

        abn             abnf=0,abnt=1
        abp             abpf=0,abpt=1
        ct              %ctpr1 ? ~IS_TAKEN_E            // not taken branch, do not restart pipeline
    }
    {
        addd,2          PC,8,PC_D                       // set pc to next insn
        addd,3          PC,4,PC_R                       // set pc to next insn
        addd,4          PC,12,PC_F                      // set pc to next insn
        ct              %ctpr3                          // restart pipeline
    }

exit:
    {
        return          %ctpr3
        addd,0          0,0,%r0
        wasted_cycles 5
    }
        ct              %ctpr3

out_of_bounds:
    {
        return          %ctpr3
        addd,0          0,1,%r0
        wasted_cycles 5
    }
        ct              %ctpr3

    .size FUNCTION_NAME, . - FUNCTION_NAME

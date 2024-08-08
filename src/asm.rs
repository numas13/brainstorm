use std::slice;

use super::Insn;

const INSN_SIZE: usize = std::mem::size_of::<Insn>();

extern "C" {
    fn bf_execute(code: *const Insn, code_size: usize, tape: *mut u8, tape_size: usize);
    fn bf_execute_dump(code: *const Insn, code_size: usize, tape: *mut u8, tape_size: usize);
}

pub(crate) fn execute(code: &[Insn], tape: &mut [u8]) {
    unsafe {
        bf_execute(
            code.as_ptr(),
            code.len() * INSN_SIZE,
            tape.as_mut_ptr(),
            tape.len(),
        );
    }
}

pub(crate) fn execute_dump(code: &[Insn], tape: &mut [u8]) {
    unsafe {
        bf_execute_dump(
            code.as_ptr(),
            code.len() * INSN_SIZE,
            tape.as_mut_ptr(),
            tape.len(),
        );
    }
}

#[no_mangle]
extern "C" fn bf_putc(c: u8) {
    print!("{}", c as char);
}

#[no_mangle]
extern "C" fn bf_getc() -> u8 {
    super::getc()
}

#[no_mangle]
extern "C" fn bf_dump_state(
    code: *const Insn,
    code_size: usize,
    tape: *mut u8,
    tape_size: usize,
    pc: usize,
    i: usize,
) {
    let bc = unsafe { slice::from_raw_parts(code, code_size / INSN_SIZE) };
    let tape = unsafe { slice::from_raw_parts(tape, tape_size) };
    super::dump_state(bc, tape, pc / INSN_SIZE, i);
}

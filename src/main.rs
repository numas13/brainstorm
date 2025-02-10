use std::{
    fmt::{self, Write},
    fs,
    io::{self, Read},
    time::Instant,
};

use crate::cli::Cli;

mod cli;

#[cfg(has_asm)]
mod asm;

#[derive(Copy, Clone, Debug, PartialEq, Eq)]
struct OutOfBoundsError;

const TAPE_SIZE: usize = 1024 * 8;

const OPCODE_CALL: i16 = 1;

const TARGET_PUTC: i16 = 1;
const TARGET_GETC: i16 = 3;

fn extract(value: u32, start: u32, len: u32) -> i32 {
    let bits = std::mem::size_of::<u32>() as u32 * 8;
    ((value << (bits - len - start)) as i32) >> (bits - len)
}

fn skip_whitespace(s: &str) -> &str {
    let offset = s.find(|c: char| "+-><[].,".contains(c)).unwrap_or(s.len());
    &s[offset..]
}

#[derive(Copy, Clone, Default)]
#[repr(transparent)]
struct Insn(u32);

impl Insn {
    fn raw(&self) -> u32 {
        self.0
    }

    fn mov(&self) -> i8 {
        extract(self.raw(), 24, 8) as i8
    }

    fn set_mov(&mut self, mov: isize) {
        assert!((-128..=127).contains(&mov));
        self.0 |= ((mov as u32) & 0xff) << 24;
    }

    fn add(&self) -> i8 {
        extract(self.raw(), 16, 8) as i8
    }

    fn set_add(&mut self, add: i8) {
        self.0 |= ((add as u32) & 0xff) << 16;
    }

    fn target(&self) -> i16 {
        extract(self.raw(), 0, 16) as i16
    }

    fn set_target(&mut self, target: i16) {
        self.0 |= (target as u32) & 0xffff;
    }

    fn set_beqz(&mut self, target: i16) {
        self.set_target(target);
    }

    fn set_bnez(&mut self, target: i16) {
        self.set_target(-target);
    }

    fn display(&self, pc: usize) -> impl fmt::Display {
        struct Display(Insn, usize);

        impl fmt::Display for Display {
            fn fmt(&self, fmt: &mut fmt::Formatter) -> fmt::Result {
                fn helper(
                    fmt: &mut fmt::Formatter,
                    value: i8,
                    inc: char,
                    dec: char,
                ) -> fmt::Result {
                    if value != 0 {
                        fmt.write_char([inc, dec][(value < 0) as usize])?;
                        write!(fmt, "{:<3}", value.abs())
                    } else {
                        fmt.write_str("    ")
                    }
                }

                let Display(insn, pc) = *self;

                helper(fmt, insn.mov(), '>', '<')?;
                fmt.write_char(' ')?;
                helper(fmt, insn.add(), '+', '-')?;
                let mut w = 9;

                match insn.target() {
                    0 => {}
                    target if target & OPCODE_CALL != 0 => {
                        match target {
                            TARGET_PUTC => write!(fmt, " .")?,
                            TARGET_GETC => write!(fmt, " ,")?,
                            _ => todo!(),
                        }
                        w += 2;
                    }
                    target => {
                        let pc = (pc + 1).wrapping_add((target / 4) as usize);
                        if target > 0 {
                            write!(fmt, " [{pc:<5}")?;
                        } else {
                            write!(fmt, " ]{pc:<5}")?;
                        }
                        w += 7;
                    }
                }

                if let Some(width) = fmt.width() {
                    while w < width {
                        w += 1;
                        fmt.write_char(' ')?;
                    }
                }

                Ok(())
            }
        }

        Display(*self, pc)
    }
}

fn parse(content: &str) -> Vec<Insn> {
    fn parse_inc<'a>(s: &'a str, inc: char, dec: char, stop: &str) -> (isize, &'a str) {
        let mut acc: isize = 0;
        for (i, c) in s.char_indices() {
            match c {
                _ if c == inc => acc = acc.wrapping_add(1),
                _ if c == dec => acc = acc.wrapping_sub(1),
                _ if stop.contains(c) => return (acc, &s[i..]),
                _ => {}
            }
        }
        (acc, &s[s.len()..])
    }

    let mut code = Vec::<Insn>::new();
    let mut loops = Vec::new();
    let mut tail = content.trim();
    let mut i = 0;
    while !tail.is_empty() {
        let s = tail;
        let mut insn = Insn::default();

        let (mov, cur) = parse_inc(s, '>', '<', "+-[],.");
        insn.set_mov(mov);

        let (add, cur) = parse_inc(cur, '+', '-', "<>[],.");
        insn.set_add(add as i8);

        let cur = skip_whitespace(cur);
        let cur = match cur.chars().next() {
            Some(c) if "[],.".contains(c) => {
                match c {
                    '[' => loops.push(i),
                    ']' => {
                        let l = loops.pop().unwrap();
                        let d = (i - l) as i16;
                        code[l].set_beqz(d * 4);
                        insn.set_bnez(d * 4);
                    }
                    '.' => insn.set_target(TARGET_PUTC),
                    ',' => insn.set_target(TARGET_GETC),
                    _ => unreachable!(),
                }
                &cur[1..]
            }
            _ => cur,
        };

        code.push(insn);
        i += 1;
        tail = cur;
    }

    code
}

fn dump(code: &[Insn]) {
    println!("Bytecode:");
    for (pc, insn) in code.iter().enumerate() {
        println!("  {pc:4}:  {:08x}  {}", insn.raw(), insn.display(pc));
    }
    println!();
}

fn dump_state(code: &[Insn], tape: &[u8], pc: usize, i: usize) {
    let insn = code[pc];
    eprint!(
        "  {pc:4}:  {:08x}  {:24} # tape[",
        insn.raw(),
        insn.display(pc)
    );
    let i = i as isize;
    let d = 3;
    let start = i - d;
    let end = i + d + 1;
    for j in start..end {
        eprint!(" ");
        if i == j {
            eprint!("|");
        }
        if let Some(v) = tape.get(j as usize) {
            eprint!("{v:3}");
        } else {
            eprint!("   ");
        }
        if i == j {
            eprint!("|");
        }
    }
    eprintln!(" ] i={i}");
}

fn getc() -> u8 {
    let mut buf = [0; 1];
    io::stdin().read_exact(&mut buf).unwrap();
    buf[0]
}

fn execute_impl<const TRACE: bool>(code: &[Insn], tape: &mut [u8]) -> Result<(), OutOfBoundsError> {
    let mut pc = 0;
    let mut i: usize = 0;

    while let Some(insn) = code.get(pc) {
        if TRACE {
            dump_state(code, tape, pc, i);
        }

        i = i.wrapping_add(insn.mov() as usize);

        let cell = tape.get_mut(i).ok_or(OutOfBoundsError)?;
        *cell = cell.wrapping_add(insn.add() as u8);

        pc += 1;
        match insn.target() {
            0 => {}
            target if target & OPCODE_CALL != 0 => match target {
                TARGET_PUTC => print!("{}", *cell as char),
                TARGET_GETC => *cell = getc(),
                _ => todo!(),
            },
            target => {
                if (*cell != 0) == (target < 0) {
                    pc = pc.wrapping_add((target / 4) as usize);
                }
            }
        }
    }

    Ok(())
}

fn execute(code: &[Insn], tape: &mut [u8]) -> Result<(), OutOfBoundsError> {
    execute_impl::<false>(code, tape)
}

fn execute_dump(code: &[Insn], tape: &mut [u8]) -> Result<(), OutOfBoundsError> {
    execute_impl::<true>(code, tape)
}

fn run(cli: &Cli, code: &[Insn]) -> Result<(), OutOfBoundsError> {
    let mut tape = vec![0_u8; TAPE_SIZE];

    if cli.trace {
        eprintln!("Trace:");

        #[cfg(has_asm)]
        if !cli.reference {
            return asm::execute_dump(code, &mut tape);
        }

        execute_dump(code, &mut tape)
    } else {
        #[cfg(has_asm)]
        if !cli.reference {
            return asm::execute(code, &mut tape);
        }

        execute(code, &mut tape)
    }
}

fn main() {
    let cli = cli::parse_cli();
    let src = match fs::read_to_string(&cli.path) {
        Ok(src) => src,
        Err(err) => {
            eprintln!("Error: Failed to read \"{}\"", cli.path);
            eprintln!();
            eprintln!("Caused by:");
            eprintln!("    0: {err}");
            std::process::exit(1);
        }
    };
    let code = parse(&src);

    if cli.dump {
        println!("{}", src.trim());
        println!();
        dump(&code);
    }

    if !cli.no_exec {
        let res = if cli.time {
            let start = Instant::now();
            let res = run(&cli, &code);
            eprintln!("Execution time {:.2?}", start.elapsed());
            res
        } else {
            run(&cli, &code)
        };

        if let Err(OutOfBoundsError) = res {
            eprintln!("error: out of bounds");
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[track_caller]
    fn test(src: &str, expect: &[u8]) {
        let code = parse(src);

        let mut tape = [0; 512];
        execute(&code, &mut tape).unwrap();
        assert_eq!(&tape[..expect.len()], expect, "rust");

        #[cfg(has_asm)]
        {
            let mut tape = [0; 512];
            asm::execute(&code, &mut tape).unwrap();
            assert_eq!(&tape[..expect.len()], expect, "assembly");
        }
    }

    #[track_caller]
    fn test_err(len: usize, src: &str) {
        let code = parse(src);

        let mut tape = vec![0; len];
        let res = execute(&code, &mut tape);
        assert_eq!(res, Err(OutOfBoundsError), "rust");

        #[cfg(has_asm)]
        {
            let mut tape = vec![0; len];
            let res = asm::execute(&code, &mut tape);
            assert_eq!(res, Err(OutOfBoundsError), "assembly");
        }
    }

    #[test]
    fn no_code() {
        test("", &[0]);
    }

    #[test]
    fn add() {
        test("++++++", &[6, 0]);
        test("------", &[250, 0]);
    }

    #[test]
    fn mov() {
        test("+>++>+++>++++>  ", &[1, 2, 3, 4, 0]);
        test(">>>++++<+++<++<+", &[1, 2, 3, 4, 0]);
    }

    #[test]
    fn br() {
        test("+++[-]>++++", &[0, 4, 0]);
        test("+>+++[-]>++", &[1, 0, 2, 0]);
        test("+++[>+++++<-]>>++++++", &[0, 15, 6, 0]);
        test("+++[>+++[>+++++<-]<-]", &[0, 0, 45, 0]);
    }

    #[test]
    fn out_of_bounds() {
        test_err(4, "<+");
        test_err(4, ">>>>>>>>+");
    }
}

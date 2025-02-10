use bpaf::*;

#[allow(dead_code)]
#[derive(Debug, Clone)]
pub struct Cli {
    pub time: bool,
    pub trace: bool,
    pub dump: bool,
    pub no_exec: bool,
    pub reference: bool,
    pub path: Option<String>,
}

pub fn parse_cli() -> Cli {
    let time = short('t')
        .long("time")
        .help("Print execution time")
        .switch();

    let trace = short('T')
        .long("trace")
        .help("Trace bytecode execution")
        .switch();

    let dump = short('d').long("dump").help("Dump bytecode").switch();

    let no_exec = short('n')
        .long("no-exec")
        .help("Do not execute brainfuck program")
        .switch();

    let reference = short('r')
        .long("reference")
        .help("Do not use executor written in assembly")
        .switch();

    let path = positional("FILE").help("File to process").optional();

    construct!(Cli {
        time,
        trace,
        dump,
        no_exec,
        reference,
        path,
    })
    .to_options()
    .descr("This is a description")
    .run()
}

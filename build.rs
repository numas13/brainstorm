fn compile(path: &str) {
    let path = format!("src/asm/{path}");
    println!("cargo:rerun-if-changed=src/asm/common.h");
    println!("cargo:rerun-if-changed={path}");
    println!("cargo:rustc-cfg=has_asm");

    cc::Build::new()
        .flag("-DDUMP_STATE=1")
        .file(&path)
        .compile("asm_dump");

    cc::Build::new()
        .flag("-DDUMP_STATE=0")
        .file(&path)
        .compile("asm");
}

fn main() {
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap_or_default();
    match target_arch.as_str() {
        "x86_64" => compile("x86_64.S"),
        "e2k" | "e2k64" => compile("e2k.S"),
        "riscv64" => compile("riscv64.S"),
        _ => {}
    }
}

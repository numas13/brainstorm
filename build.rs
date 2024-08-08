#[allow(dead_code)]
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
    #[cfg(target_arch = "x86_64")]
    compile("x86_64.S");

    #[cfg(any(target_arch = "e2k64", target_arch = "e2k"))]
    compile("e2k.S");
}

//! Codex-style terminal title control via OSC 0.
//!
//! Mirrors openai/codex `terminal_title.rs`:
//!   write!(f, "\x1b]0;{}\x07", title)
//!
//! Usage:
//!   gts-title set  --tty /dev/ttys022 --title "foo"
//!   gts-title spin --tty /dev/ttys022 --label PixelCity --flag /path/busy.flag \
//!                  [--interval-ms 100] [--idle "PixelCity - Grok"]

use std::env;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process;
use std::thread;
use std::time::{Duration, Instant};

const BRAILLE: &[&str] = &["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const ASCII: &[&str] = &["|", "/", "-", "\\"];
/// Codex-style attention frames when the agent is waiting for the user.
const ALERT: &[&str] = &["[!]", "[.]"];
const MAX_TITLE_CHARS: usize = 240;

fn usage() -> ! {
    eprintln!(
        "\
gts-title — Codex-style OSC 0 title helper

  gts-title set  --tty PATH --title TEXT
  gts-title spin --tty PATH --label NAME --flag PATH \\
                 [--interval-ms 100] [--idle TEXT] [--ascii] [--alert] \\
                 [--pid-file PATH] [--last-title-file PATH]
"
    );
    process::exit(2);
}

fn sanitize_title(raw: &str) -> String {
    // Strip controls / bidi-ish junk; collapse whitespace; bound length.
    let mut out = String::with_capacity(raw.len().min(MAX_TITLE_CHARS * 4));
    let mut last_space = false;
    for ch in raw.chars() {
        let is_control = ch.is_control() || ch == '\u{200B}' || ch == '\u{200C}' || ch == '\u{200D}'
            || ch == '\u{FEFF}' || ('\u{202A}'..='\u{202E}').contains(&ch)
            || ('\u{2066}'..='\u{2069}').contains(&ch);
        if is_control {
            continue;
        }
        if ch.is_whitespace() {
            if !last_space && !out.is_empty() {
                out.push(' ');
                last_space = true;
            }
            continue;
        }
        last_space = false;
        out.push(ch);
        if out.chars().count() >= MAX_TITLE_CHARS {
            break;
        }
    }
    while out.ends_with(' ') {
        out.pop();
    }
    out
}

/// OSC 0 + BEL — same framing as Codex terminal_title.rs.
fn osc0_payload(title: &str) -> Vec<u8> {
    let t = sanitize_title(title);
    let mut buf = Vec::with_capacity(t.len() + 8);
    buf.extend_from_slice(b"\x1b]0;");
    buf.extend_from_slice(t.as_bytes());
    buf.push(0x07); // BEL
    buf
}

fn open_tty(path: &Path) -> io::Result<File> {
    OpenOptions::new().write(true).open(path)
}

fn write_title(tty: &mut File, title: &str) -> io::Result<()> {
    let payload = osc0_payload(title);
    tty.write_all(&payload)?;
    tty.flush()?;
    Ok(())
}

fn write_title_path(tty_path: &Path, title: &str) -> io::Result<()> {
    let mut f = open_tty(tty_path)?;
    write_title(&mut f, title)
}

fn parse_args() -> Vec<String> {
    env::args().skip(1).collect()
}

fn take_flag(args: &mut Vec<String>, name: &str) -> Option<String> {
    if let Some(i) = args.iter().position(|a| a == name) {
        args.remove(i);
        if i < args.len() {
            return Some(args.remove(i));
        }
    }
    None
}

fn has_flag(args: &mut Vec<String>, name: &str) -> bool {
    if let Some(i) = args.iter().position(|a| a == name) {
        args.remove(i);
        return true;
    }
    false
}

fn cmd_set(mut args: Vec<String>) {
    let tty = take_flag(&mut args, "--tty").unwrap_or_else(|| usage());
    let title = take_flag(&mut args, "--title").unwrap_or_else(|| usage());
    if let Err(e) = write_title_path(Path::new(&tty), &title) {
        eprintln!("gts-title set failed: {e}");
        process::exit(1);
    }
}

fn cmd_spin(mut args: Vec<String>) {
    let tty = take_flag(&mut args, "--tty").unwrap_or_else(|| usage());
    let label = take_flag(&mut args, "--label").unwrap_or_else(|| usage());
    let flag = take_flag(&mut args, "--flag").unwrap_or_else(|| usage());
    // Default idle = label only (may be empty). Never invent "{label} - Grok".
    let idle = take_flag(&mut args, "--idle").unwrap_or_else(|| label.clone());
    let ascii = has_flag(&mut args, "--ascii");
    let alert = has_flag(&mut args, "--alert");
    let interval_ms: u64 = take_flag(&mut args, "--interval-ms")
        .and_then(|s| s.parse().ok())
        .unwrap_or(if alert { 500 } else { 100 });
    let pid_file = take_flag(&mut args, "--pid-file");
    let last_title_file = take_flag(&mut args, "--last-title-file");

    if let Some(ref p) = pid_file {
        let _ = fs::write(p, format!("{}\n", process::id()));
    }

    let frames: &[&str] = if alert {
        ALERT
    } else if ascii {
        ASCII
    } else {
        BRAILLE
    };
    let flag_path = PathBuf::from(&flag);
    let tty_path = PathBuf::from(&tty);

    let mut file = match open_tty(&tty_path) {
        Ok(f) => f,
        Err(e) => {
            eprintln!("gts-title open tty {tty}: {e}");
            process::exit(1);
        }
    };

    // Best-effort restore on signals.
    let idle_for_handler = idle.clone();
    let tty_for_handler = tty.clone();
    ctrlc_shim(move || {
        let _ = write_title_path(Path::new(&tty_for_handler), &idle_for_handler);
        process::exit(0);
    });

    let mut i: usize = 0;
    let mut last = String::new();
    let interval = Duration::from_millis(interval_ms);

    while flag_path.is_file() {
        let t0 = Instant::now();
        let frame = frames[i % frames.len()];
        let title = if label.is_empty() {
            frame.to_string()
        } else {
            format!("{frame} {label}")
        };
        if title != last {
            if let Err(e) = write_title(&mut file, &title) {
                eprintln!("gts-title write: {e}");
                break;
            }
            last = title.clone();
            if let Some(ref p) = last_title_file {
                let _ = fs::write(p, &title);
            }
        }
        i = i.wrapping_add(1);

        let elapsed = t0.elapsed();
        if elapsed < interval {
            // Sleep in small slices so flag removal is noticed quickly.
            let mut left = interval - elapsed;
            while left > Duration::ZERO && flag_path.is_file() {
                let slice = left.min(Duration::from_millis(20));
                thread::sleep(slice);
                left = left.saturating_sub(slice);
            }
        }
    }

    // Always strip spinner glyph when we stop.
    let _ = write_title(&mut file, &idle);
    if let Some(ref p) = last_title_file {
        let _ = fs::write(p, &idle);
    }
}

/// Minimal SIGINT/SIGTERM hook without extra crates.
fn ctrlc_shim<F: Fn() + Send + Sync + 'static>(handler: F) {
    use std::sync::OnceLock;
    static HANDLER: OnceLock<Box<dyn Fn() + Send + Sync>> = OnceLock::new();
    let _ = HANDLER.set(Box::new(handler));

    extern "C" fn c_handler(_: libc::c_int) {
        if let Some(h) = HANDLER.get() {
            h();
        }
    }

    unsafe {
        libc::signal(libc::SIGINT, c_handler as usize);
        libc::signal(libc::SIGTERM, c_handler as usize);
    }
}

// Tiny libc bindings so we don't pull the full `libc` crate.
mod libc {
    #![allow(non_camel_case_types)]
    pub type c_int = i32;
    pub const SIGINT: c_int = 2;
    pub const SIGTERM: c_int = 15;
    extern "C" {
        pub fn signal(sig: c_int, handler: usize) -> usize;
    }
}

fn main() {
    let mut args = parse_args();
    if args.is_empty() {
        usage();
    }
    let cmd = args.remove(0);
    match cmd.as_str() {
        "set" => cmd_set(args),
        "spin" => cmd_spin(args),
        "-h" | "--help" | "help" => usage(),
        other => {
            eprintln!("unknown command: {other}");
            usage();
        }
    }
}

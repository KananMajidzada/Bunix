use console;
use rt;

// A placeholder command loop. The real shell will be a 9P client; for now this
// only proves that input and output work end to end.

def BUFSZ: size = 256;

export fn run(mem_mib: u64) never = {
	let line: [BUFSZ]u8 = [0...];
	for (true) {
		console::print("bunix> ");
		const n = readline(line[..]);
		if (n > 0) {
			exec(mem_mib, line[..n]);
		};
	};
};

fn readline(buf: []u8) size = {
	let n = 0z;
	for (true) {
		const ch = console::getch();
		if (ch == '\n' || ch == '\r') {
			console::putc('\n': u8);
			return n;
		} else if (ch == '\b') {
			if (n > 0) {
				n -= 1;
				console::print("\b \b");
			};
		} else if (ch >= ' ' && ch < 0x7F) {
			if (n < len(buf)) {
				buf[n] = ch;
				n += 1;
				console::putc(ch);
			};
		};
	};
};

fn exec(mem_mib: u64, line: []u8) void = {
	if (eq(line, "help")) {
		console::println("commands: help, mem, halt");
	} else if (eq(line, "mem")) {
		console::print("available: ");
		console::printnum(mem_mib);
		console::println(" MiB");
	} else if (eq(line, "halt")) {
		rt::halt();
	} else {
		console::print("unknown command: ");
		console::write(line);
		console::putc('\n': u8);
	};
};

// Compares a line buffer against a string literal by reinterpreting it as a
// string; the equality then goes through rt::strcmp.
fn eq(line: []u8, s: str) bool = {
	let a = *(&line: *str);
	return a == s;
};

use lib;
use rt;

// tail [-n lines] [file...]
//
// The last lines of a file, ten unless the command says otherwise. The file is
// read whole and the tail is kept in a ring, so asking for more lines than the
// ring holds asks for everything there is.

def RING: size = 1024;

let rptr: [RING]uintptr = [0...];
let rlen: [RING]size = [0...];
let slot: size = 0;
let held: size = 0;
let want: size = 10;

fn note(line: []u8) bool = {
	rptr[slot] = lib::at_ptr(line);
	rlen[slot] = lib::at_len(line);
	slot = (slot + 1) % RING;
	if (held < RING) {
		held += 1;
	};
	return true;
};

fn tail_file(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("tail: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	slot = 0;
	held = 0;
	lib::each_line(text, &note);
	const show = if (want < held) want else held;
	// The ring holds the newest lines, so the oldest of the ones being shown
	// comes first.
	let start = (slot + RING - show) % RING;
	for (let i = 0z; i < show; i += 1) {
		const k = (start + i) % RING;
		rt::write(lib::view(rptr[k], rlen[k]));
		rt::println("");
	};
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	for (let f = 0z; pos < len(args) && args[pos] == ('-': u8) && len(args) > pos + 1; f += 1) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) > 1 && tok[1] == ('n': u8)) {
			let (v, next) = lib::flag_val(args, pos, 2, want: u64);
			want = v: size;
			pos = next;
			continue;
		};
		if (len(tok) > 1 && lib::is_digit(tok[1])) {
			want = lib::parse_int(tok[1..], want: u64): size;
			pos = lib::skip_space(args, pos + len(tok));
			continue;
		};
		rt::print("tail: unknown option ");
		rt::println(*(&tok: *str));
		return;
	};

	let nfiles = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		if (k > 0) {
			lib::banner(path);
		};
		tail_file(path);
		nfiles += 1;
		pos = next;
	};
	if (nfiles == 0) {
		rt::println("usage: tail [-n lines] [file...]");
	};
};
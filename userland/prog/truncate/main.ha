use lib;
use posix;
use rt;

// truncate [-s] <path> <bytes>
//
// Cut a file down to a length. What was past that point is gone, and there is
// no syscall here that throws bytes away in place, so the file is read back
// and the part that is to stay written out again. That makes it a whole-file
// operation underneath: on a file larger than the memory the kernel has it
// would run out before it ran short of work.
//
// A length longer than the file is left alone unless -s is given, because
// making a file longer means writing zeros into the new space — a hole is not
// something this filesystem has a way to write — and that is worth having to
// ask for. With -s the file is set to that length whichever way it has to
// move.

// How much is moved at a time. The buffer is a literal rather than a named
// size because this language will not take a name for the length of an array,
// and a file could be copied a byte at a time as well as any other amount.
let copybuf: [512]u8 = [0...];
let zerobuf: [512]u8 = [0...];

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let grow = false;

	if (pos < len(args) && args[pos] == ('-': u8)) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) != 2 || tok[1] != ('s': u8)) {
			rt::print("truncate: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		grow = true;
		pos = lib::skip_space(args, pos + len(tok));
	};

	let names: [2][]u8 = [[], []];
	let n = 0z;
	for (let k = 0z; pos < len(args) && n < 2; k += 1) {
		let (word, next) = lib::next_arg(args, pos);
		pos = next;
		names[n] = word;
		n += 1;
	};
	if (n < 2) {
		rt::println("usage: truncate [-s] <path> <bytes>");
		return;
	};
	const path = names[0];
	const want = lib::parse_int(names[1], 0);

	const in = posix::open(*(&path: *str), posix::O_RDONLY);
	if (in < 0) {
		rt::print("truncate: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let held = 0u64;
	const held_before = posix::lseek(in, 0, posix::SEEK_END);
	if (held_before > 0) {
		held = held_before: u64;
	};

	// Cutting a file down is the ordinary thing and always happens. Making
	// one longer is the one that needs asking for. Deciding before opening
	// the file for writing matters: that open empties it, so a length that
	// changes nothing has to be turned away first or the file is lost.
	let keep = held;
	if (want < held) {
		keep = want;
	} else if (grow && want > held) {
		keep = want;
	};
	if (keep == held) {
		posix::close(in);
		rt::print("already ");
		rt::printnum(held);
		rt::println(" bytes");
		return;
	};

	const out = posix::open(*(&path: *str),
		posix::O_WRONLY | posix::O_CREAT | posix::O_TRUNC);
	if (out < 0) {
		posix::close(in);
		rt::print("truncate: cannot write ");
		rt::println(*(&path: *str));
		return;
	};

	// Copy the first `keep` bytes straight through, then pad with zeroes if
	// the file is being made longer.
	let copied: u64 = 0;
	_ = posix::lseek(in, 0, posix::SEEK_SET);
	for (let k = 0z; copied < keep; k += 1) {
		let want_now: size = 512;
		if (keep - copied < (want_now: u64)) {
			want_now = (keep - copied): size;
		};
		const got = posix::read(in, copybuf[..want_now]);
		if (got == 0) {
			break;
		};
		_ = posix::write(out, copybuf[..got]);
		copied += got: u64;
	};
	posix::close(in);

	for (let k = 0z; copied < keep; k += 1) {
		let want_now: size = 512;
		if (keep - copied < (want_now: u64)) {
			want_now = (keep - copied): size;
		};
		_ = posix::write(out, zerobuf[..want_now]);
		copied += want_now: u64;
	};
	posix::close(out);
	rt::println("truncated");
};
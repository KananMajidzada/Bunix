use lib;
use posix;
use rt;

// split [-l lines] <file> <prefix>
//
// Break a file into pieces. The first thousand lines go in one file, the next
// thousand in the next, and so on, named prefixaa, prefixab and on until the
// alphabet runs out and it starts again at prefixba.
//
// Two letters rather than one, because a thousand pieces fit on a disk and a
// hundred do not fit on a screen. The point of splitting a file is usually
// that something can hold one piece of it, and that something should not have
// to be told which letter it got.

def DEFAULT: size = 1000;

// Two letters count 676 ways, and this is how many pieces that allows.
def MAXPIECES: size = 676;

let perpiece: size = DEFAULT;
let prefix: []u8 = [];
let npieces: size = 0;
let lineno: size = 0;

let fd: int = -1;
let path: [256]u8 = [0...];
let pathlen: size = 0;
let newline: [1]u8 = ['\n'];

fn piecepath(n: size) []u8 = {
	if (len(prefix) + 2 > len(path)) {
		return [];
	};
	let k = 0z;
	for (let i = 0z; i < len(prefix); i += 1) {
		path[k] = prefix[i];
		k += 1;
	};
	// The two letters are a number in base twenty-six, most significant
	// first, so piece zero is aa and piece twenty-six is ba.
	path[k] = ('a' + ((n / 26) % 26)): u8;
	path[k + 1] = ('a' + (n % 26)): u8;
	pathlen = k + 2;
	return path[..pathlen];
};

fn close_piece() void = {
	if (fd >= 0) {
		posix::close(fd);
		fd = -1;
		// Each piece is named as it is finished. Working the names out from
		// the prefix afterwards is possible but tedious, and this is the
		// list of files that now exist.
		const p = path[..pathlen];
		rt::println(*(&p: *str));
	};
};

fn feed(line: []u8) bool = {
	if (lineno % perpiece == 0) {
		close_piece();
		if (npieces >= MAXPIECES) {
			rt::println("split: that is the last piece the alphabet allows");
			return false;
		};
		const p = piecepath(npieces);
		if (len(p) == 0) {
			rt::println("split: the prefix is too long to put two letters after");
			return false;
		};
		npieces += 1;
		fd = posix::open(*(&p: *str),
			posix::O_WRONLY | posix::O_CREAT | posix::O_TRUNC);
		if (fd < 0) {
			rt::print("split: cannot write ");
			rt::println(*(&p: *str));
			return false;
		};
	};

	// The line comes here without the newline that ended it, and a piece of a
	// file whose lines were run together would be one enormous line, so the
	// newline is put back. Writing it on its own rather than into a joined
	// buffer keeps a line longer than any buffer here from being cut short.
	_ = posix::write(fd, line);
	_ = posix::write(fd, newline[..]);
	lineno += 1;
	return true;
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);

	if (pos < len(args) && args[pos] == ('-': u8)) {
		const tok = args[pos..lib::token_end(args, pos)];
		if (len(tok) != 2 || tok[1] != ('l': u8)) {
			rt::print("split: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		pos = lib::skip_space(args, pos + len(tok));
		let (count, next) = lib::next_arg(args, pos);
		if (len(count) == 0) {
			rt::println("usage: split [-l lines] <file> <prefix>");
			return;
		};
		pos = next;
		const nlines = lib::parse_int(count, 0);
		perpiece = DEFAULT;
		if (nlines > 0 && nlines < 100000) {
			perpiece = nlines: size;
		};
	};

	// The flag came off the front, so the file and the prefix are whatever is
	// left of the line rather than the first two words of it.
	let names: [2][]u8 = [[], []];
	let n = 0z;
	for (let k = 0z; pos < len(args) && n < 2; k += 1) {
		let (word, next) = lib::next_arg(args, pos);
		pos = next;
		names[n] = word;
		n += 1;
	};
	if (n < 2) {
		rt::println("usage: split [-l lines] <file> <prefix>");
		return;
	};
	prefix = names[1];

	const text = lib::slurp(names[0]);
	if (len(text) == 0) {
		rt::print("split: cannot read ");
		rt::println(*(&names[0]: *str));
		return;
	};
	lib::each_line(text, &feed);
	close_piece();
	if (npieces == 0) {
		rt::println("split: nothing to split");
	} else {
		rt::printnum(npieces: u64);
		rt::println(if (npieces == 1) " piece" else " pieces");
	};
	lib::release(text);
};
use lib;
use rt;

// nm [path]
//
// The symbol table of an ELF file, the way nm prints it. Two symbols in here
// are worth knowing by name: the loader looks for _start to know where to
// begin, and for __image_end to know how much of the image to clear before it
// runs anything. That pair is the whole contract between what the compiler
// emits and what the kernel will run, and this is how to look at it.

def NSYM: size = 4096;
def NOFOUND: size = ~0z;

// A symbol needs three things kept: where its entry is, because the type and
// the value live there, and where its name is, because that is somewhere else
// entirely. Storing the name as a length alone would mean looking it up again
// for every symbol printed.
let sentry: [NSYM]size = [0...];
let sname: [NSYM]size = [0...];
let snamelen: [NSYM]size = [0...];
let nsym: size = 0;
let dropped: size = 0;

let empty: []u8 = [];

fn read16(b: []u8, at: size) u16 = {
	return (b[at]: u16) | ((b[at + 1]: u16) << 8);
};

fn read32(b: []u8, at: size) u32 = {
	return (b[at]: u32) | ((b[at + 1]: u32) << 8)
		| ((b[at + 2]: u32) << 16) | ((b[at + 3]: u32) << 24);
};

fn read64(b: []u8, at: size) u64 = {
	let v: u64 = 0;
	for (let i = 0u64; i < 8; i += 1) {
		v |= (b[at + i: size]: u64) << (i * 8);
	};
	return v;
};

fn hexdig(v: u8) u8 = {
	if (v < 10) {
		return ('0': u8) + v;
	};
	return ('a': u8) + (v - 10);
};

fn hex(v: u64, places: size) void = {
	let buf: [16]u8 = [0...];
	let i = len(buf);
	let x = v;
	// A zero has no digits to shift out, and without this it would come out
	// as nothing at all rather than as a row of zeros.
	if (x == 0) {
		i -= 1;
		buf[i] = ('0': u8);
	} else {
		for (let k = 0u64; k < 16 && x > 0; k += 1) {
			i -= 1;
			buf[i] = hexdig((x % 16): u8);
			x /= 16;
		};
	};
	for (let k = len(buf) - i; k < places; k += 1) {
		rt::putc('0': u8);
	};
	rt::write(buf[i..]);
};

// The letter nm puts in front of a symbol to say what kind of thing it is.
// Both halves live in the one st_info byte: the kind of thing in the low four
// bits, and whether it is local to this file or global in the high four.
fn letter(info: u8, shndx: u16) u8 = {
	const kind = info & 0x0f;
	const global = (info >> 4) & 0x0f == 1;
	// A symbol in no section at all is one this file expects somewhere else
	// to have, which is a stronger statement than merely being untyped.
	if (shndx == 0) {
		return if (global) 'U' else 'u';
	};
	if (kind == 0) {
		return if (global) 'g' else 'l';
	};
	if (kind == 1) {
		return 'G';
	};
	if (kind == 2) {
		return 'W';
	};
	if (kind == 3) {
		return 'U';
	};
	if (kind == 4) {
		return 'F';
	};
	if (kind == 10) {
		return 'B';
	};
	if (kind == 11) {
		return 'D';
	};
	return '?';
};

fn show(b: []u8, want: []u8, filtering: bool) void = {
	for (let i = 0z; i < nsym; i += 1) {
		const nm = b[sname[i]..sname[i] + snamelen[i]];
		if (filtering && !lib::contains(nm, want)) {
			continue;
		};
		const e = sentry[i];
		rt::putc(letter(b[e + 4], read16(b, e + 6)));
		rt::putc(' ': u8);
		// st_value is the second field of the entry, not the first: the
		// first is the offset of the name.
		hex(read64(b, e + 8), 16);
		rt::putc(' ': u8);
		rt::println(*(&nm: *str));
	};
};

// The section headers are where the symbol table and the string table it
// points into are found. Neither has a fixed place in the file, so both have
// to be looked for.
fn symbols(b: []u8, want: []u8, filtering: bool) void = {
	const shoff = read64(b, 40): size;
	const shnum = read16(b, 60): size;
	const shent = read16(b, 58): size;
	if (shoff == 0 || shnum == 0 || shent == 0 || shoff + shnum * shent > len(b)) {
		rt::println("nm: no section headers, so no symbol table");
		return;
	};

	let symtab: size = NOFOUND;
	let symsize: size = 0;
	let strtab: size = NOFOUND;
	let strsz: size = 0;
	for (let i = 0z; i < shnum; i += 1) {
		const sh = shoff + i * shent;
		// The first field of a section header is its type: 2 is a symbol
		// table, 3 the string table. A symbol table's link field says which
		// section holds the names, so that is where the strings are found.
		if (read32(b, sh + 4) == 2) {
			symtab = read64(b, sh + 24): size;
			symsize = read64(b, sh + 32): size;
			const link = read32(b, sh + 40): size;
			if (shoff + link * shent + 40 <= len(b)) {
				const strsec = shoff + link * shent;
				strtab = read64(b, strsec + 24): size;
				strsz = read64(b, strsec + 32): size;
			};
		};
	};
	if (symtab == NOFOUND || strtab == NOFOUND
			|| symtab + symsize > len(b) || strtab + strsz > len(b)) {
		rt::println("nm: no symbol table");
		return;
	};

	nsym = 0;
	dropped = 0;
	// An entry is 24 bytes. A name offset of zero means the section markers
	// and the end of the table, none of which have anything to print.
	for (let at = symtab; at + 24 <= symtab + symsize; at += 24) {
		const off = read32(b, at): size;
		if (off == 0 || off >= strsz) {
			continue;
		};
		let n = 0z;
		for (let i = off; i < strsz && b[strtab + i] != 0; i += 1) {
			n += 1;
		};
		if (n == 0) {
			continue;
		};
		if (nsym == NSYM) {
			dropped += 1;
			continue;
		};
		sentry[nsym] = at;
		sname[nsym] = strtab + off;
		snamelen[nsym] = n;
		nsym += 1;
	};
	if (nsym == 0) {
		rt::println("nm: the symbol table is empty");
		return;
	};
	show(b, want, filtering);
	if (dropped > 0) {
		rt::print("nm: ");
		rt::printnum(dropped: u64);
		rt::println(" symbols did not fit");
	};
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	// nm takes the symbols to look for as bare words, which is the one thing
	// it does that is worth having: a table of a program's exports is long
	// and only two or three names in it are ever wanted.
	let filtering = false;
	for (let k = 0z; pos < len(args); k += 1) {
		let (tok, next) = lib::next_arg(args, pos);
		if (tok[0] == ('-': u8)) {
			rt::print("nm: unknown option ");
			rt::println(*(&tok: *str));
			return;
		};
		pos = next;
		filtering = true;
	};
	const path = lib::arg_n(args, 0);
	if (len(path) == 0) {
		rt::println("usage: nm [path] [symbol...]");
		return;
	};
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("nm: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	if (len(text) < 64) {
		rt::println("nm: too short to be an ELF file");
		lib::release(text);
		return;
	};
	if (text[0] != 0x7f || text[1] != ('E': u8) || text[2] != ('L': u8)
			|| text[3] != ('F': u8)) {
		rt::println("nm: not an ELF file");
		lib::release(text);
		return;
	};
	symbols(text, lib::arg_n(args, 1), filtering);
	lib::release(text);
};
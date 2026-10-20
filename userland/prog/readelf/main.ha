use lib;
use rt;

// readelf [path]
//
// The parts of an ELF header worth reading. The loader in the kernel walks
// exactly these fields to decide where a linked executable goes and what to
// map, so this is a way to see the decision rather than infer it from a
// failure. A program Bunix compiled can be run by path, and this is what says
// why it can.

def CLASS64: u8 = 2;
def ET_REL: u16 = 1;
def ET_EXEC: u16 = 2;
def ET_DYN: u16 = 3;

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

fn field(name: str, value: str) void = {
	rt::print("  ");
	rt::print(name);
	for (let i = 0u64; i < 22; i += 1) {
		rt::putc(' ': u8);
	};
	rt::println(value);
};

// The name of an object file type, since a number here says very little.
fn etype(t: u16) str = {
	if (t == ET_REL) {
		return "REL (an object file, to be linked)";
	};
	if (t == ET_EXEC) {
		return "EXEC (a program to run)";
	};
	if (t == ET_DYN) {
		return "DYN (a shared object or a program)";
	};
	return "something else";
};

fn phname(t: u32) str = {
	if (t == 1) {
		return "LOAD";
	};
	if (t == 6) {
		return "PHDR";
	};
	if (t == 0x6474E550) {
		return "GNU_EH_FRAME";
	};
	if (t == 0x6474E551) {
		return "GNU_STACK";
	};
	if (t == 0x6474E553) {
		return "GNU_PROPERTY";
	};
	return "-";
};

fn load(f: []u8) size = {
	const off = lib::at_ptr(f);
	if (len(f) < 64) {
		rt::println("readelf: too short to be an ELF file");
		return 0;
	};
	const b = lib::view(off, len(f));
	if (b[0] != 0x7f || b[1] != ('E': u8) || b[2] != ('L': u8) || b[3] != ('F': u8)) {
		rt::println("readelf: not an ELF file");
		return 0;
	};

	field("class", if (b[4] == CLASS64) "ELF64" else "not ELF64");
	field("type", etype(read16(b, 16)));

	rt::print("  machine             ");
	hex(read16(b, 18), 4);
	rt::println("");

	hexline("entry", read64(b, 24));
	hexline("phoff", read64(b, 32));
	hexline("shoff", read64(b, 40));
	hexline("flags", read32(b, 48));
	hexline("ehsize", read16(b, 52));
	hexline("phentsize", read16(b, 54));
	hexline("phnum", read16(b, 56): u64);
	hexline("shentsize", read16(b, 58): u64);
	hexline("shnum", read16(b, 60): u64);
	hexline("shstrndx", read16(b, 62): u64);

	const phoff = read64(b, 32): size;
	const phnum = read16(b, 56): size;
	const phent = read16(b, 54): size;
	if (phnum == 0 || phent == 0 || phoff + phnum * phent > len(f)) {
		return 0;
	};
	rt::println("");
	rt::println("");
	rt::println("program headers:");
	for (let i = 0z; i < phnum; i += 1) {
		const p = phoff + i * phent;
		// Two lines a header, each a run of labelled pairs. A single line of
		// six sixteen-digit numbers is a hundred and six columns, and this
		// console is eighty.
		rt::print("  ");
		rt::print(phname(read32(b, p)));
		rt::print("  off ");
		hex(read64(b, p + 8), 16);
		rt::print("  vaddr ");
		hex(read64(b, p + 16), 16);
		rt::println("");
		rt::print("       file ");
		hex(read64(b, p + 32), 16);
		rt::print("  mem ");
		hex(read64(b, p + 40), 16);
		rt::print("  flags ");
		hex(read32(b, p + 4), 8);
		rt::println("");
	};
	sections(b);
	return len(f);
};

// The section table, which is where a symbol table would be found. Naming the
// sections is the quickest way to see whether one is there at all.
fn sections(b: []u8) void = {
	const shoff = read64(b, 40): size;
	const shnum = read16(b, 60): size;
	const shent = read16(b, 58): size;
	const shstrndx = read16(b, 62): size;
	if (shoff == 0 || shnum == 0 || shent == 0 || shoff + shnum * shent > len(b)) {
		return;
	};
	const strsh = shoff + shstrndx * shent;
	if (strsh + 40 > len(b)) {
		return;
	};
	const strtab = read64(b, strsh + 24): size;
	const strsz = read64(b, strsh + 32): size;
	if (strtab + strsz > len(b)) {
		return;
	};
	rt::println("");
	rt::println("sections:");
	rt::println("   nr type          addr            off             size");
	for (let i = 0z; i < shnum; i += 1) {
		const sh = shoff + i * shent;
		rt::print("  ");
		num2(i: u64, 2);
		rt::putc(' ': u8);
		rt::print(shtype(read32(b, sh + 4)));
		rt::print("  ");
		hex(read64(b, sh + 16), 16);
		rt::print("  ");
		hex(read64(b, sh + 24), 16);
		rt::print("  ");
		hex(read64(b, sh + 32), 16);
		rt::println("");
	};
};

// The name a section table holds, taken out of the table of section names.
fn shtype(t: u32) str = {
	if (t == 0) {
		return "NULL      ";
	};
	if (t == 1) {
		return "PROGBITS  ";
	};
	if (t == 2) {
		return "SYMTAB    ";
	};
	if (t == 3) {
		return "STRTAB    ";
	};
	if (t == 4) {
		return "RELA      ";
	};
	if (t == 8) {
		return "NOBITS    ";
	};
	return "-         ";
};

fn num2(v: u64, places: size) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	let x = v;
	for (let k = 0u64; k < 20 && x > 0; k += 1) {
		i -= 1;
		buf[i] = ((x % 10): u8) + ('0': u8);
		x /= 10;
	};
	for (let k = i; k < places; k += 1) {
		rt::putc(' ': u8);
	};
	rt::write(buf[i..]);
};

fn hexline(name: str, v: u64) void = {
	rt::print("  ");
	rt::print(name);
	for (let i = 0u64; i < 22; i += 1) {
		rt::putc(' ': u8);
	};
	hex(v, 16);
	rt::println("");
};

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

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	const path = lib::arg_n(args, 0);
	if (len(path) == 0) {
		rt::println("usage: readelf [path]");
		return;
	};
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("readelf: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	load(text);
	lib::release(text);
};
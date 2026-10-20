use lib;
use rt;

// md5sum [file...]
//
// The MD5 of each file, in hex, beside its name. The shape is the one md5sum
// prints everywhere, so what this says can be checked against a host without
// either side having to be told which is which.
//
// MD5 is not a cipher and should not be used as one. It is here to name a file
// by what is in it: to see whether two copies have drifted apart, and to match
// a file that was fetched against the sum published beside it. Anything that
// has to be unguessable wants a different function.

def S: [64]size = [
	7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
	5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
	4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
	6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
];

// The sine table RFC 1321 prints, kept as it is given rather than worked out:
// these are awkward as binary coded decimals in most implementations, and a
// floating point sine here would not be the same number twice.
const K: [64]u32 = [
	0xD76AA478, 0xE8C7B756, 0x242070DB, 0xC1BDCEEE,
	0xF57C0FAF, 0x4787C62A, 0xA8304613, 0xFD469501,
	0x698098D8, 0x8B44F7AF, 0xFFFF5BB1, 0x895CD7BE,
	0x6B901122, 0xFD987193, 0xA679438E, 0x49B40821,
	0xF61E2562, 0xC040B340, 0x265E5A51, 0xE9B6C7AA,
	0xD62F105D, 0x02441453, 0xD8A1E681, 0xE7D3FBC8,
	0x21E1CDE6, 0xC33707D6, 0xF4D50D87, 0x455A14ED,
	0xA9E3E905, 0xFCEFA3F8, 0x676F02D9, 0x8D2A4C8A,
	0xFFFA3942, 0x8771F681, 0x6D9D6122, 0xFDE5380C,
	0xA4BEEA44, 0x4BDECFA9, 0xF6BB4B60, 0xBEBFBC70,
	0x289B7EC6, 0xEAA127FA, 0xD4EF3085, 0x04881D05,
	0xD9D4D039, 0xE6DB99E5, 0x1FA27CF8, 0xC4AC5665,
	0xF4292244, 0x432AFF97, 0xAB9423A7, 0xFC93A039,
	0x655B59C3, 0x8F0CCC92, 0xFFEFF47D, 0x85845DD1,
	0x6FA87E4F, 0xFE2CE6E0, 0xA3014314, 0x4E0811A1,
	0xF7537E82, 0xBD3AF235, 0x2AD7D2BB, 0xEB86D391,
];
fn rotl(v: u32, n: size) u32 = {
	return (v << (n: u32)) | (v >> (32 - (n: u32)));
};

// The sixteen words of the block being worked on. MD5 takes them little
// endian, which is the other way round from the same bytes read on a big
// endian machine.
fn words(block: []u8, x: *[16]u32) void = {
	for (let i = 0z; i < 16; i += 1) {
		x[i] = (block[i * 4]: u32)
			| ((block[i * 4 + 1]: u32) << 8)
			| ((block[i * 4 + 2]: u32) << 16)
			| ((block[i * 4 + 3]: u32) << 24);
	};
};

fn digest(text: []u8, out: *[16]u8) void = {
	let a: u32 = 0x67452301;
	let b: u32 = 0xEFCDAB89;
	let c: u32 = 0x98BADCFE;
	let d: u32 = 0x10325476;

	let x: [16]u32 = [0...];
	// Every block of sixty-four bytes, and the last one padded out: a single
	// 0x80 byte, then zeros, then the length in bits as eight little endian
	// bytes.
	let padded = ((len(text) + 8) / 64 + 1) * 64;
	let block: [128]u8 = [0...];
	// The message length in bits, in eight little endian bytes at the end of
	// the last block. A file long enough to need the high half of this is
	// not one this kernel has the memory for, but the rule is written out
	// whole rather than truncated on purpose.
	const bits: u64 = (len(text): u64) * 8;
	let hi = bits / 0x100000000;
	let lo = bits & 0xFFFFFFFF;

	for (let at = 0z; at < padded; at += 64) {
		for (let i = 0z; i < 64 && at + i < len(text); i += 1) {
			block[i] = text[at + i];
		};
		// The 0x80 and the length are written one after the other, and a
		// message short enough to need only one block puts both in the same
		// one. Making them one branch or the other loses whichever is in the
		// else, which is how this came to hash everything wrongly.
		if (at <= len(text) && len(text) < at + 64) {
			block[len(text) - at] = 0x80: u8;
		};
		if (at + 64 == padded) {
			block[56] = (lo & 0xFF): u8;
			block[57] = ((lo >> 8) & 0xFF): u8;
			block[58] = ((lo >> 16) & 0xFF): u8;
			block[59] = ((lo >> 24) & 0xFF): u8;
			block[60] = (hi & 0xFF): u8;
			block[61] = ((hi >> 8) & 0xFF): u8;
			block[62] = ((hi >> 16) & 0xFF): u8;
			block[63] = ((hi >> 24) & 0xFF): u8;
		};
		words(block[..], &x);

		for (let i = 0z; i < 64; i += 1) {
			let f: u32 = 0;
			let g: size = 0;
			if (i < 16) {
				f = (b & c) | (~b & d);
				g = i;
			} else if (i < 32) {
				f = (d & b) | (~d & c);
				g = (5 * i + 1) % 16;
			} else if (i < 48) {
				f = b ^ c ^ d;
				g = (3 * i + 5) % 16;
			} else {
				f = c ^ (b | ~d);
				g = (7 * i) % 16;
			};
			f = f + a + K[i] + x[g];
			f = rotl(f, S[i]);
			a = d;
			d = c;
			c = b;
			b = b + f;
		};
		a += 0x67452301;
		b += 0xEFCDAB89;
		c += 0x98BADCFE;
		d += 0x10325476;
	};

	let words_out: [4]u32 = [a, b, c, d];
	for (let i = 0z; i < 4; i += 1) {
		const v = words_out[i];
		out[i * 4] = (v & 0xFF): u8;
		out[i * 4 + 1] = ((v >> 8) & 0xFF): u8;
		out[i * 4 + 2] = ((v >> 16) & 0xFF): u8;
		out[i * 4 + 3] = ((v >> 24) & 0xFF): u8;
	};
};

const HEX: str = "0123456789abcdef";

// A str only becomes a slice at run time, so this cannot be a value the file
// holds and has to be asked for.
fn alpha() []u8 = {
	return *(&HEX: *[]u8);
};

fn hexdigest(d: []u8) void = {
	const a = alpha();
	for (let i = 0z; i < len(d); i += 1) {
		rt::putc(a[(d[i] >> 4): size]);
		rt::putc(a[(d[i] & 0x0f): size]);
	};
};

fn one(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("md5sum: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let out: [16]u8 = [0...];
	digest(text, &out);
	hexdigest(out[..]);
	rt::putc(' ': u8);
	rt::println(*(&path: *str));
	lib::release(text);
};

export @symbol("main") fn main() void = {
	const args = *(&rt::arg(): *[]u8);
	let pos = lib::skip_space(args, 0);
	let n = 0z;
	for (let k = 0z; pos < len(args); k += 1) {
		let (path, next) = lib::next_arg(args, pos);
		pos = next;
		one(path);
		n += 1;
	};
	if (n == 0) {
		rt::println("usage: md5sum <file>...");
	};
};

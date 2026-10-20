use lib;
use rt;

// sha256sum [file...]
//
// The SHA-256 of each file, in hex, beside its name. The shape is the one
// sha256sum prints everywhere.
//
// SHA-256 is one of the three in the family FIPS 180-4 picked from, and the
// one to reach for when a sum has to mean something: md5sum is here for
// matching a file against a sum published long ago and nothing more.

// The first thirty-two bits of the fractional parts of the square roots of the
// first eight primes. They are what they are and are kept as given: a
// floating point square root here would not be the same number twice.
const H0: [8]u32 = [
	0x6A09E667, 0xBB67AE85, 0x3C6EF372, 0xA54FF53A,
	0x510E527F, 0x9B05688C, 0x1F83D9AB, 0x5BE0CD19,
];

// The first thirty-two bits of the fractional parts of the cube roots of the
// first sixty-four primes, one per round. The two tables are made the same way
// out of the same primes and are nothing alike, which is the sort of thing
// worth writing down.
const K: [64]u32 = [
	0x428A2F98, 0x71374491, 0xB5C0FBCF, 0xE9B5DBA5,
	0x3956C25B, 0x59F111F1, 0x923F82A4, 0xAB1C5ED5,
	0xD807AA98, 0x12835B01, 0x243185BE, 0x550C7DC3,
	0x72BE5D74, 0x80DEB1FE, 0x9BDC06A7, 0xC19BF174,
	0xE49B69C1, 0xEFBE4786, 0x0FC19DC6, 0x240CA1CC,
	0x2DE92C6F, 0x4A7484AA, 0x5CB0A9DC, 0x76F988DA,
	0x983E5152, 0xA831C66D, 0xB00327C8, 0xBF597FC7,
	0xC6E00BF3, 0xD5A79147, 0x06CA6351, 0x14292967,
	0x27B70A85, 0x2E1B2138, 0x4D2C6DFC, 0x53380D13,
	0x650A7354, 0x766A0ABB, 0x81C2C92E, 0x92722C85,
	0xA2BFE8A1, 0xA81A664B, 0xC24B8B70, 0xC76C51A3,
	0xD192E819, 0xD6990624, 0xF40E3585, 0x106AA070,
	0x19A4C116, 0x1E376C08, 0x2748774C, 0x34B0BCB5,
	0x391C0CB3, 0x4ED8AA4A, 0x5B9CCA4F, 0x682E6FF3,
	0x748F82EE, 0x78A5636F, 0x84C87814, 0x8CC70208,
	0x90BEFFFA, 0xA4506CEB, 0xBEF9A3F7, 0xC67178F2,
];

const HEX: str = "0123456789abcdef";

// A str only becomes a slice at run time, so this cannot be a value the file
// holds and has to be asked for.
fn alpha() []u8 = {
	return *(&HEX: *[]u8);
};

fn ror(v: u32, n: size) u32 = {
	return (v >> (n: u32)) | (v << (32 - (n: u32)));
};

fn hexdigest(d: []u8) void = {
	const a = alpha();
	for (let i = 0z; i < len(d); i += 1) {
		rt::putc(a[(d[i] >> 4): size]);
		rt::putc(a[(d[i] & 0x0f): size]);
	};
};

fn digest(text: []u8, out: *[32]u8) void = {
	const h = H0;
	let w: [64]u32 = [0...];

	// SHA-256 pads like MD5 but writes the length big endian, so the last
	// eight bytes are put down the other way round from the rest.
	let padded = ((len(text) + 8) / 64 + 1) * 64;
	let block: [128]u8 = [0...];
	const bits: u64 = (len(text): u64) * 8;
	let hi = bits / 0x100000000;
	let lo = bits & 0xFFFFFFFF;

	for (let at = 0z; at < padded; at += 64) {
		for (let i = 0z; i < 64 && at + i < len(text); i += 1) {
			block[i] = text[at + i];
		};
		if (at + 64 > len(text) && at <= len(text)) {
			block[len(text) - at] = 0x80: u8;
		};
		if (at + 64 == padded) {
			block[56] = ((hi >> 24) & 0xFF): u8;
			block[57] = ((hi >> 16) & 0xFF): u8;
			block[58] = ((hi >> 8) & 0xFF): u8;
			block[59] = (hi & 0xFF): u8;
			block[60] = ((lo >> 24) & 0xFF): u8;
			block[61] = ((lo >> 16) & 0xFF): u8;
			block[62] = ((lo >> 8) & 0xFF): u8;
			block[63] = (lo & 0xFF): u8;
		};

		// Sixteen big endian words, spread out over sixty-four according to
		// the schedule the standard gives: the first sixteen are the block,
		// and the rest are built from the ones before them.
		for (let i = 0z; i < 16; i += 1) {
			const at4 = i * 4;
			w[i] = ((block[at4]: u32) << 24)
				| ((block[at4 + 1]: u32) << 16)
				| ((block[at4 + 2]: u32) << 8)
				| (block[at4 + 3]: u32);
		};
		for (let i = 16z; i < 64; i += 1) {
			const w15 = w[i - 15];
			const w2 = w[i - 2];
			const s0 = ror(w15, 7) ^ ror(w15, 18) ^ (w15 >> 3);
			const s1 = ror(w2, 17) ^ ror(w2, 19) ^ (w2 >> 10);
			w[i] = w[i - 16] + s0 + w[i - 7] + s1;
		};

		let a = h[0];
		let b = h[1];
		let c = h[2];
		let d = h[3];
		let e = h[4];
		let f = h[5];
		let g = h[6];
		let hh = h[7];

		for (let i = 0z; i < 64; i += 1) {
			const s1 = ror(e, 6) ^ ror(e, 11) ^ ror(e, 25);
			const ch = (e & f) ^ (~e & g);
			const t1 = hh + s1 + ch + K[i] + w[i];
			const s0 = ror(a, 2) ^ ror(a, 13) ^ ror(a, 22);
			const maj = (a & b) ^ (a & c) ^ (b & c);
			const t2 = s0 + maj;
			hh = g;
			g = f;
			f = e;
			e = d + t1;
			d = c;
			c = b;
			b = a;
			a = t1 + t2;
		};

		const r = [a + h[0], b + h[1], c + h[2], d + h[3],
			e + h[4], f + h[5], g + h[6], hh + h[7]];
		for (let i = 0z; i < 8; i += 1) {
			out[i * 4] = ((r[i] >> 24) & 0xFF): u8;
			out[i * 4 + 1] = ((r[i] >> 16) & 0xFF): u8;
			out[i * 4 + 2] = ((r[i] >> 8) & 0xFF): u8;
			out[i * 4 + 3] = (r[i] & 0xFF): u8;
		};
	};
};

fn one(path: []u8) void = {
	const text = lib::slurp(path);
	if (len(text) == 0) {
		rt::print("sha256sum: cannot read ");
		rt::println(*(&path: *str));
		return;
	};
	let out: [32]u8 = [0...];
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
		rt::println("usage: sha256sum <file>...");
	};
};
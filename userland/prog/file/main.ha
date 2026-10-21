use lib;
use rt;

// Says what a file is, from the few bytes at the front of it. Nothing here
// is sure of itself: a file is only what its first bytes say it is.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	if (n < 1) {
		rt::println("usage: file <path>...");
		return;
	};
	for (let i = 0z; i < n; i += 1) {
		const path = words[i];
		if (!rt::exists(*(&path: *str))) {
			rt::print("file: no such file: ");
			rt::println(*(&path: *str));
			continue;
		};
		let buf: [64]u8 = [0...];
		const flen = rt::readfile(*(&path: *str), buf[..]);
		rt::print(*(&path: *str));
		rt::print(": ");
		rt::println(kind(buf[..flen]));
	};
};

// What the first bytes of a file say it is.
fn kind(head: []u8) str = {
	if (len(head) >= 4 && head[0] == 0x7F && head[1] == ('E': u8)
			&& head[2] == ('L': u8) && head[3] == ('F': u8)) {
		return "an executable";
	};
	if (len(head) >= 2 && head[0] == ('#': u8) && head[1] == ('!': u8)) {
		return "a script";
	};
	if (len(head) >= 4 && head[0] == 0x1F && head[1] == 0x8B) {
		return "compressed data";
	};
	if (len(head) >= 8 && head[0] == 0x89 && head[1] == ('P': u8)
			&& head[2] == ('N': u8) && head[3] == ('G': u8)) {
		return "a picture";
	};
	if (len(head) >= 5 && head[0] == ('B': u8) && head[1] == ('U': u8)
			&& head[2] == ('N': u8) && head[3] == ('X': u8)) {
		return "a Bunix filesystem";
	};
	// Text is anything with no byte that cannot be shown.
	let text = true;
	for (let i = 0z; i < len(head); i += 1) {
		const c = head[i];
		if (c != ('\n': u8) && c != ('\t': u8) && c != ('\r': u8)
				&& (c < (' ': u8) || c >= 0x7F)) {
			text = false;
			break;
		};
	};
	if (text) {
		return "text";
	};
	return "data";
};

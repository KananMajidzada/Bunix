use lib;
use posix;
use rt;

let recursive = false;

// Copies files through the POSIX interface, a block at a time. With -r a
// whole tree is copied. When more than one file is named the last name is a
// directory the others are put in.
export @symbol("main") fn main() void = {
	const a = rt::arg();
	const arg = *(&a: *[]u8);
	let words: [lib::MAXWORDS][]u8 = [[]...];
	const n = lib::split(arg, &words);
	let pos: [lib::MAXWORDS][]u8 = [[]...];
	let npos = 0z;
	for (let i = 0z; i < n; i += 1) {
		const w = words[i];
		if (len(w) > 1 && w[0] == ('-': u8)) {
			let ok = true;
			for (let j = 1z; j < len(w); j += 1) {
				if (w[j] == ('r': u8) || w[j] == ('R': u8)) {
					recursive = true;
				} else {
					ok = false;
				};
			};
			if (ok) {
				continue;
			};
		};
		if (npos < lib::MAXWORDS) {
			pos[npos] = w;
			npos += 1;
		};
	};
	if (npos < 2) {
		rt::println("usage: cp [-r] <src>... <dst>");
		return;
	};
	const dst = pos[npos - 1];
	// The last name is a directory when it is one, and it has to be one
	// when there is more than one file to put in it.
	if (npos > 2 || rt::isdir(*(&dst: *str))) {
		for (let i = 0z; i + 1 < npos; i += 1) {
			let target: [512]u8 = [0...];
			const tl = join(target[..], dst, base(pos[i]));
			copy_one(pos[i], target[..tl]);
		};
		return;
	};
	copy_one(pos[0], dst);
};

// One source and one target.
fn copy_one(src: []u8, dst: []u8) void = {
	if (!rt::isdir(*(&src: *str))) {
		copy_file(src, dst);
		return;
	};
	if (!recursive) {
		rt::print("cp: is a directory: ");
		rt::println(*(&src: *str));
		return;
	};
	if (!rt::exists(*(&dst: *str))) {
		_ = rt::mkdir(*(&dst: *str));
	};
	let buf: [4096]u8 = [0...];
	const n = rt::readdir(*(&src: *str), buf[..]);
	let start = 0z;
	for (let i = 0z; i <= n; i += 1) {
		if (i == n || buf[i] == ('\n': u8)) {
			if (i > start) {
				// The name is put in a buffer of its own, since the
				// listing buffer is used again by the copy below.
				let nm: [256]u8 = [0...];
				let k = 0z;
				for (let j = start; j < i && k < len(nm); j += 1) {
					nm[k] = buf[j];
					k += 1;
				};
				let s: [512]u8 = [0...];
				const sl = join(s[..], src, nm[..k]);
				let t: [512]u8 = [0...];
				const tl = join(t[..], dst, nm[..k]);
				copy_one(s[..sl], t[..tl]);
			};
			start = i + 1;
		};
	};
};

// One file, a block at a time.
fn copy_file(src: []u8, dst: []u8) void = {
	const in = posix::open(*(&src: *str), posix::O_RDONLY);
	if (in < 0) {
		rt::print("cp: cannot read ");
		rt::println(*(&src: *str));
		return;
	};
	const out = posix::open(*(&dst: *str), posix::O_WRONLY | posix::O_CREAT);
	if (out < 0) {
		posix::close(in);
		rt::print("cp: cannot create ");
		rt::println(*(&dst: *str));
		return;
	};
	let buf: [512]u8 = [0...];
	for (true) {
		const n = posix::read(in, buf[..]);
		if (n == 0) {
			break;
		};
		_ = posix::write(out, buf[..n]);
	};
	posix::close(in);
	posix::close(out);
	rt::print("copied ");
	rt::print(*(&src: *str));
	rt::print(" to ");
	rt::println(*(&dst: *str));
};

// The last part of a path.
fn base(path: []u8) []u8 = {
	let end = len(path);
	for (end > 1 && path[end - 1] == ('/': u8)) {
		end -= 1;
	};
	let start = 0z;
	for (let i = 0z; i < end; i += 1) {
		if (path[i] == ('/': u8)) {
			start = i + 1;
		};
	};
	return path[start..end];
};

// A path made of a directory and a name in it, written into the given
// buffer.
fn join(buf: []u8, dir: []u8, name: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(dir) && n + 1 < len(buf); i += 1) {
		buf[n] = dir[i];
		n += 1;
	};
	if (n > 0 && buf[n - 1] != ('/': u8) && n + 1 < len(buf)) {
		buf[n] = ('/': u8);
		n += 1;
	};
	for (let i = 0z; i < len(name) && n < len(buf); i += 1) {
		buf[n] = name[i];
		n += 1;
	};
	return n;
};

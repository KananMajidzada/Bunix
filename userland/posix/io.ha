// A small POSIX shim over the native file calls. The kernel hands a file over
// in one read and takes it back in one write, so open slurps a file into a
// buffer and close flushes one out. That keeps the mismatch between POSIX and
// the native interface in one place; a ported program sees the ordinary
// open/read/write/close shape.
use rt;

export def O_RDONLY: int = 0;
export def O_WRONLY: int = 1;
export def O_RDWR: int = 2;
export def O_CREAT: int = 0x40;
export def O_TRUNC: int = 0x200;

export def SEEK_SET: int = 0;
export def SEEK_CUR: int = 1;
export def SEEK_END: int = 2;

export def STDIN: int = 0;
export def STDOUT: int = 1;
export def STDERR: int = 2;

def NFD: int = 8;
def BUFCAP: size = 65536;

type hdr = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

fn as_slice(p: uintptr, n: size) []u8 = {
	const h = hdr { data = p, length = n, capacity = n };
	return *(&h: *[]u8);
};

let used: [NFD]bool = [false...];
let wronly: [NFD]bool = [false...];
let path: [NFD]str = [""...];
let base: [NFD]uintptr = [0...];
let length: [NFD]size = [0...];
let cursor: [NFD]size = [0...];

fn slot() int = {
	let i = 3;
	for (i < NFD && used[i]) {
		i += 1;
	};
	return if (i == NFD) -1 else i;
};

export fn open(p: str, flags: int) int = {
	const i = slot();
	if (i < 0) {
		return -1;
	};
	const mem = rt::malloc(BUFCAP);
	const b = match (mem) {
	case null =>
		return -1;
	case let q: *opaque =>
		yield q: uintptr;
	};
	const j = i: size;
	used[j] = true;
	path[j] = p;
	base[j] = b;
	length[j] = 0;
	cursor[j] = 0;
	if ((flags & (O_WRONLY | O_RDWR)) != 0) {
		wronly[j] = true;
		if ((flags & O_CREAT) != 0) {
			_ = rt::create(p);
		};
		return i;
	};
	wronly[j] = false;
	length[j] = rt::readfile(p, as_slice(b, BUFCAP));
	return i;
};

export fn read(fd: int, buf: []u8) size = {
	if (fd == STDIN) {
		let n = 0z;
		for (n < len(buf)) {
			const c = rt::getchar();
			buf[n] = c;
			n += 1;
			if (c == ('\n': u8)) {
				break;
			};
		};
		return n;
	};
	if (fd < 0 || fd >= NFD || !used[fd: size] || wronly[fd: size]) {
		return 0;
	};
	const j = fd: size;
	let n = length[j] - cursor[j];
	if (n > len(buf)) {
		n = len(buf);
	};
	const src = as_slice(base[j] + cursor[j], n);
	for (let k = 0z; k < n; k += 1) {
		buf[k] = src[k];
	};
	cursor[j] += n;
	return n;
};

export fn write(fd: int, buf: []u8) size = {
	if (fd == STDOUT || fd == STDERR) {
		rt::write(buf);
		return len(buf);
	};
	if (fd < 0 || fd >= NFD || !used[fd: size] || !wronly[fd: size]) {
		return 0;
	};
	const j = fd: size;
	let n = 0z;
	for (n < len(buf) && length[j] < BUFCAP) {
		*((base[j] + length[j]): *u8) = buf[n];
		length[j] += 1;
		n += 1;
	};
	return n;
};

export fn close(fd: int) int = {
	if (fd < 0 || fd >= NFD || !used[fd: size]) {
		return -1;
	};
	const j = fd: size;
	if (wronly[j]) {
		_ = rt::writefile(path[j], as_slice(base[j], length[j]));
	};
	rt::free_((base[j]: *opaque));
	used[j] = false;
	return 0;
};

export fn lseek(fd: int, off: int, whence: int) int = {
	if (fd < 0 || fd >= NFD || !used[fd: size]) {
		return -1;
	};
	const j = fd: size;
	let n = cursor[j]: int;
	if (whence == SEEK_SET) {
		n = off;
	} else if (whence == SEEK_CUR) {
		n += off;
	} else if (whence == SEEK_END) {
		n = (length[j]: int) + off;
	};
	if (n < 0) {
		n = 0;
	};
	if ((n: size) > length[j]) {
		n = length[j]: int;
	};
	cursor[j] = n: size;
	return n;
};

export fn strlen(s: *const u8) size = {
	const p = (s: uintptr): *[*]u8;
	let n = 0z;
	for (p[n] != 0) {
		n += 1;
	};
	return n;
};

export fn strcmp(a: *const u8, b: *const u8) int = {
	const pa = (a: uintptr): *[*]u8;
	const pb = (b: uintptr): *[*]u8;
	let i = 0z;
	for (pa[i] != 0 && pa[i] == pb[i]) {
		i += 1;
	};
	return (pa[i]: int) - (pb[i]: int);
};

export fn strncmp(a: *const u8, b: *const u8, n: size) int = {
	const pa = (a: uintptr): *[*]u8;
	const pb = (b: uintptr): *[*]u8;
	let i = 0z;
	for (i < n && pa[i] != 0 && pa[i] == pb[i]) {
		i += 1;
	};
	if (i == n) {
		return 0;
	};
	return (pa[i]: int) - (pb[i]: int);
};

export fn strcpy(dst: *u8, src: *const u8) *u8 = {
	const pd = (dst: uintptr): *[*]u8;
	const ps = (src: uintptr): *[*]u8;
	let i = 0z;
	for (ps[i] != 0) {
		pd[i] = ps[i];
		i += 1;
	};
	pd[i] = 0;
	return dst;
};

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

export def O_APPEND: int = 0x400;
export def O_BINARY: int = 0;

export def PROT_READ: int = 1;
export def PROT_WRITE: int = 2;
export def PROT_EXEC: int = 4;
export def MAP_SHARED: int = 1;
export def MAP_PRIVATE: int = 2;
export def MAP_FIXED: int = 0x10;
export def MAP_ANONYMOUS: int = 0x20;

export def F_SETLKW: int = 7;
export def F_RDLCK: int = 0;
export def F_WRLCK: int = 1;
export def F_UNLCK: int = 2;

export def SIGFPE: int = 8;
export def SIGILL: int = 4;
export def SIGSEGV: int = 11;
export def SIGBUS: int = 7;
export def SIGABRT: int = 6;
export def SIGUSR1: int = 10;
export def SIGCHLD: int = 17;

export def SA_SIGINFO: int = 4;

export def R_OK: int = 4;
export def W_OK: int = 2;
export def X_OK: int = 1;

def NFD: int = 16;
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
	// Sized from the file itself. A fixed cap silently truncated anything
	// bigger, which made wc under-report and grep miss the tail of a file.
	let want = rt::filesize(p);
	if (want < 1) {
		want = BUFCAP;
	} else {
		want += 1;
	};
	const mem = rt::malloc(want);
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
	length[j] = rt::readfile(p, as_slice(b, want));
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

export fn getcwd(buf: *u8, nsize: size) *u8 = {
	const cwd = rt::getcwd();
	const cb = *(&cwd: *[]u8);
	const pb = (buf: uintptr): *[*]u8;
	let n = len(cb);
	if (n >= nsize) { n = nsize - 1; };
	for (let i = 0z; i < n; i += 1) { pb[i] = cb[i]; };
	pb[n] = 0;
	return buf;
};

export fn chdir(path: *const u8) int = {
	return if (rt::chdir(*(&path: *str))) 0 else -1;
};

export fn mkdir(path: *const u8, mode: int) int = {
	return if (rt::mkdir(*(&path: *str))) 0 else -1;
};

export fn rmdir(path: *const u8) int = {
	return if (rt::remove(*(&path: *str))) 0 else -1;
};

export fn access(path: *const u8, mode: int) int = {
	return 0;
};

export fn unlink(path: *const u8) int = {
	return if (rt::remove(*(&path: *str))) 0 else -1;
};

export fn rename(oldpath: *const u8, newpath: *const u8) int = {
	return -1;
};

// The kernel clock is /proc/uptime, a decimal count of seconds since boot.
export fn time(tloc: nullable *u64) u64 = {
	let buf: [32]u8 = [0...];
	const n = rt::readfile("/proc/uptime", buf[..]);
	let v: u64 = 0;
	for (let i = 0z; i < n; i += 1) {
		const c = buf[i];
		if (c < ('0': u8) || c > ('9': u8)) {
			break;
		};
		v = v * 10 + ((c - ('0': u8)): u64);
	};
	match (tloc) {
	case null => void;
	case let p: *u64 => *p = v;
	};
	return v;
};

export fn gettimeofday(tv: nullable *u64, tz: *opaque) int = {
	const t = time(null);
	match (tv) {
	case null => void;
	case let p: *u64 => *p = t;
	};
	return 0;
};

export fn signal(sig: int, handler: *opaque) nullable *opaque = {
	return null;
};

export fn sigaction(sig: int, act: *opaque, oldact: *opaque) int = {
	return 0;
};

export fn fork() int = {
	return -1;
};

export fn execv(path: *const u8, argv: *const *const u8) int = {
	return -1;
};

export fn waitpid(pid: int, status: *int, options: int) int = {
	return -1;
};

export fn pipe(fds: *int) int = {
	return -1;
};

export fn dup(fd: int) int = {
	return -1;
};

export fn dup2(oldfd: int, newfd: int) int = {
	return -1;
};

export fn fcntl(fd: int, cmd: int, arg: int) int = {
	return 0;
};

export fn fstat(fd: int, st: *opaque) int = {
	if (fd < 0 || fd >= NFD || !used[fd: size]) {
		return -1;
	};
	const j = fd: size;
	// struct stat: st_size sits at offset 48 on x86-64.
	const p = st: uintptr;
	for (let i = 0z; i < 8; i += 1) {
		*((p + 48 + (i: uintptr)): *u8) = (length[j] >> (i * 8)): u8;
	};
	return 0;
};

// tcc maps input files and anonymous scratch. A file's bytes were already
// slurped at open, so a mapping just copies them into fresh pages.
export fn mmap(addr: *opaque, nlen: size, prot: int, flags: int, fd: int, off: int) nullable *opaque = {
	let pages = (nlen + 4095z) / 4096z;
	if (pages == 0) {
		pages = 1;
	};
	const p = rt::page_alloc(pages: u64);
	if (p == 0) {
		return null;
	};
	if (fd >= 0 && fd < NFD && used[fd: size] && !wronly[fd: size]) {
		const j = fd: size;
		if (off >= 0 && (off: size) < length[j]) {
			let n = length[j] - (off: size);
			if (n > nlen) {
				n = nlen;
			};
			const src = as_slice(base[j] + (off: size), n);
			for (let i = 0z; i < n; i += 1) {
				*((p + i): *u8) = src[i];
			};
		};
	};
	return p: *opaque;
};

export fn munmap(addr: *opaque, nlen: size) int = {
	return 0;
};

export type dirent = struct {
	d_ino: u64,
	d_off: u64,
	d_reclen: u16,
	d_type: u8,
	d_name: [256]u8,
};

export type DIR = struct {
	buf: [4096]u8,
	nlen: size,
	off: size,
	ent: dirent,
};

export fn opendir(name: *const u8) nullable *DIR = {
	const mem = rt::malloc(size(DIR));
	const d = match (mem) {
	case null => return null;
	case let q: *opaque => yield q: *DIR;
	};
	d.off = 0;
	d.nlen = rt::readdir(*(&name: *str), d.buf[..]);
	return d;
};

// The kernel lists a directory as newline-separated names, so readdir just
// hands back one line at a time.
export fn readdir(dirp: *DIR) nullable *dirent = {
	if (dirp.off >= dirp.nlen) {
		return null;
	};
	const start = dirp.off;
	let i = start;
	for (i < dirp.nlen && dirp.buf[i] != ('\n': u8)) {
		i += 1;
	};
	const l = i - start;
	let k = 0z;
	for (k < l && k < 255z) {
		dirp.ent.d_name[k] = dirp.buf[start + k];
		k += 1;
	};
	dirp.ent.d_name[k] = 0;
	dirp.ent.d_ino = 0;
	dirp.ent.d_off = (i + 1): u64;
	dirp.ent.d_reclen = l: u16;
	dirp.ent.d_type = 0;
	dirp.off = if (i < dirp.nlen) i + 1 else dirp.nlen;
	return &dirp.ent;
};

export fn closedir(dirp: *DIR) int = {
	rt::free_((dirp: *opaque));
	return 0;
};

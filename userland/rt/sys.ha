type shdr = struct {
	data: uintptr,
	length: size,
	capacity: size,
};

@symbol("rt.sys_exit") fn sys_exit() never;
@symbol("rt.sys_write") fn sys_write(ptr: uintptr, n: size) u64;
@symbol("rt.sys_read") fn sys_read(
	pptr: uintptr,
	plen: size,
	dptr: uintptr,
	dlen: size,
) u64;
@symbol("rt.sys_alloc") fn sys_alloc(pages: u64) uintptr;
@symbol("rt.sys_writefile") fn sys_writefile(
	pptr: uintptr,
	plen: size,
	dptr: uintptr,
	dlen: size,
) u64;
@symbol("rt.sys_readchr") fn sys_readchr() u64;
@symbol("rt.sys_yield") fn sys_yield() u64;
@symbol("rt.sys_create") fn sys_create(pptr: uintptr, plen: size, isdir: u64) u64;
@symbol("rt.sys_remove") fn sys_remove(pptr: uintptr, plen: size) u64;
@symbol("rt.sys_readdir") fn sys_readdir(pptr: uintptr, plen: size, dptr: uintptr, dlen: size) u64;
@symbol("rt.sys_halt") fn sys_halt() never;
@symbol("rt.sys_spawn") fn sys_spawn(pptr: uintptr, plen: size) u64;
@symbol("rt.sys_spawn_shared") fn sys_spawn_shared(pptr: uintptr, plen: size) u64;
@symbol("rt.sys_alive") fn sys_alive(id: u64) u64;
@symbol("rt.sys_fresh") fn sys_fresh() u64;
@symbol("rt.sys_stat") fn sys_stat(pptr: uintptr, plen: size, sizeptr: uintptr, modeptr: uintptr) u64;
@symbol("rt.sys_screen") fn sys_screen(rowsp: uintptr, colsp: uintptr) u64;
@symbol("rt.sys_chdir") fn sys_chdir(pptr: uintptr, plen: size) u64;
@symbol("rt.sys_pwd") fn sys_pwd(dptr: uintptr, dlen: size) u64;
@symbol("rt.sys_ps") fn sys_ps(dptr: uintptr, dlen: size) u64;
@symbol("rt.sys_kill") fn sys_kill(id: u64) u64;
@symbol("rt.sys_readat") fn sys_readat(pptr: uintptr, plen: size, dptr: uintptr, dlen: size, off: u64) u64;
@symbol("rt.sys_writeat") fn sys_writeat(pptr: uintptr, plen: size, dptr: uintptr, dlen: size, off: u64) u64;
@symbol("rt.sys_appendfile") fn sys_append(
	pptr: uintptr,
	plen: size,
	dptr: uintptr,
	dlen: size,
) u64;
@symbol("rt.sys_redirect") fn sys_redirect(pptr: uintptr, plen: size, mode: u64) u64;
@symbol("rt.arg_ptr") let arg_ptr: u64;
@symbol("rt.arg_len") let arg_len: u64;

export fn arg() str = {
	let h = shdr {
		data = arg_ptr: uintptr,
		length = arg_len: size,
		capacity = arg_len: size,
	};
	return *(&h: *str);
};

export fn write(buf: []u8) void = {
	const h = *(&buf: *shdr);
	sys_write(h.data, h.length);
};

export fn print(s: str) void = {
	write(*(&s: *[]u8));
};

export fn println(s: str) void = {
	print(s);
	print("\n");
};

export fn printnum(n: u64) void = {
	let buf: [20]u8 = [0...];
	let i = len(buf);
	if (n == 0) {
		i -= 1;
		buf[i] = '0': u8;
	} else {
		let v = n;
		for (v > 0) {
			i -= 1;
			buf[i] = ((v % 10): u8) + ('0': u8);
			v /= 10;
		};
	};
	write(buf[i..]);
};

export fn exit() never = sys_exit();

export fn page_alloc(pages: u64) uintptr = sys_alloc(pages);

export fn putc(ch: u8) void = {
	let b: [1]u8 = [ch];
	write(b[..]);
};

export fn getchar() u8 = {
	for (true) {
		const c = sys_readchr();
		if (c != 0) {
			return (c & 0xFF): u8;
		};
		_ = sys_yield();
	};
};

// One byte if one is waiting, else zero.
export fn readchr() u8 = (sys_readchr() & 0xFF): u8;

// True once when a new window was opened and wants its prompt.
export fn fresh() bool = sys_fresh() != 0;

export fn readfile(path: str, dest: []u8) size = {
	const p = *(&path: *shdr);
	const d = *(&dest: *shdr);
	return sys_read(p.data, p.length, d.data, d.length): size;
};

// Scratch for the size syscall: bytes at offset 0, kind at offset 8. A
// package-level buffer, since the call needs their addresses.
let statbuf: [16]u8 = [0...];

fn stat_of(path: str, bytes: *u64, kind: *u32) bool = {
	const p = *(&path: *shdr);
	statbuf[0] = 0;
	statbuf[8] = 0;
	if (sys_stat(p.data, p.length, &statbuf[0]: uintptr, &statbuf[8]: uintptr) == 0) {
		return false;
	};
	*bytes = *((&statbuf[0]: uintptr): *u64);
	*kind = *((&statbuf[8]: uintptr): *u32);
	return true;
};

// Whether a path names something that is there. The size syscall answers
// without moving any bytes, which a one-byte read could not: it cannot tell an
// empty file from a name that is not there.
export fn exists(path: str) bool = {
	let n: u64 = 0;
	let k: u32 = 0;
	return stat_of(path, &n, &k);
};

// The size of a file in bytes, or zero when there is nothing at that path.
export fn filesize(path: str) u64 = {
	let n: u64 = 0;
	let k: u32 = 0;
	if (!stat_of(path, &n, &k)) {
		return 0;
	};
	return n;
};

// Whether a path names a directory. The size call answers with the kind
// alongside the length, so this costs no more than asking for the size did.
export fn isdir(path: str) bool = {
	let n: u64 = 0;
	let k: u32 = 0;
	if (!stat_of(path, &n, &k)) {
		return false;
	};
	return k != 0;
};

// Moves the process into a directory. A relative path is from where it
// already is.
export fn chdir(path: str) bool = {
	const p = *(&path: *shdr);
	return sys_chdir(p.data, p.length) != 0;
};

// The processes that are running, one per line. The number of the process
// comes first, and then the command it was started with.
let psbuf: [4096]u8 = [0...];

export fn ps() []u8 = {
	const n = sys_ps(&psbuf[0]: uintptr, len(psbuf));
	return psbuf[..n];
};

// Stops a process.
export fn kill(id: u64) bool = {
	return sys_kill(id) != 0;
};

// Reads a file from an offset, which is what a file too big to be held in
// memory needs.
export fn readat(path: str, off: u64, dest: []u8) size = {
	const p = *(&path: *shdr);
	const d = *(&dest: *shdr);
	return sys_readat(p.data, p.length, d.data, d.length, off): size;
};

// Writes to a file at an offset.
export fn writeat(path: str, data: []u8, off: u64) size = {
	const p = *(&path: *shdr);
	const d = *(&data: *shdr);
	return sys_writeat(p.data, p.length, d.data, d.length, off): size;
};

// Adds to the end of a file, making it when it is not there yet.
export fn appendto(path: str, data: []u8) size = {
	const p = *(&path: *shdr);
	const d = *(&data: *shdr);
	return sys_append(p.data, p.length, d.data, d.length): size;
};

// Sends the output of this process to a file instead of the screen, or back
// to the screen when the path is empty. The file is emptied first when the
// add flag is not set.
export fn redirect(path: str, add: bool) bool = {
	const p = *(&path: *shdr);
	const mode = if (add) 2 else 1;
	return sys_redirect(p.data, p.length, mode: u64) != 0;
};

// Where the process is, as an absolute path.
let cwdb: [512]u8 = [0...];

export fn getcwd() str = {
	const n = sys_pwd(&cwdb[0]: uintptr, len(cwdb));
	return *(&cwdb[..n]: *str);
};

// The console size in rows and columns. The kernel's text console interprets
// the escape sequences an editor draws with, so a program can lay itself out to
// fit whatever screen there is.
let screenbuf: [8]u8 = [0...];

fn screen() bool = {
	screenbuf[0] = 0;
	screenbuf[4] = 0;
	return sys_screen(&screenbuf[0]: uintptr, &screenbuf[4]: uintptr) != 0;
};

export fn screen_rows() u64 = {
	if (!screen()) {
		return 25;
	};
	return *((&screenbuf[0]: uintptr): *u32): u64;
};

export fn screen_cols() u64 = {
	if (!screen()) {
		return 80;
	};
	return *((&screenbuf[4]: uintptr): *u32): u64;
};

export fn writefile(path: str, data: []u8) size = {
	const p = *(&path: *shdr);
	const d = *(&data: *shdr);
	return sys_writefile(p.data, p.length, d.data, d.length): size;
};

export fn mkdir(path: str) bool = {
	const p = *(&path: *shdr);
	return sys_create(p.data, p.length, 1) != 0;
};

export fn create(path: str) bool = {
	const p = *(&path: *shdr);
	return sys_create(p.data, p.length, 0) != 0;
};

export fn remove(path: str) bool = {
	const p = *(&path: *shdr);
	return sys_remove(p.data, p.length) != 0;
};

export fn readdir(path: str, dest: []u8) size = {
	const p = *(&path: *shdr);
	const d = *(&dest: *shdr);
	return sys_readdir(p.data, p.length, d.data, d.length): size;
};

export fn haltsys() never = sys_halt();

export fn spawn(path: str) u64 = {
	const p = *(&path: *shdr);
	return sys_spawn(p.data, p.length);
};

// Starts a program that shares this process's namespace.
export fn spawn_shared(path: str) u64 = {
	const p = *(&path: *shdr);
	return sys_spawn_shared(p.data, p.length);
};

export fn alive(id: u64) bool = {
	return sys_alive(id) != 0;
};

export fn cop() void = {
	_ = sys_yield();
};

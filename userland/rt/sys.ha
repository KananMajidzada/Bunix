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
@symbol("rt.sys_halt") fn sys_halt() never;
@symbol("rt.sys_spawn") fn sys_spawn(pptr: uintptr, plen: size) u64;
@symbol("rt.sys_alive") fn sys_alive(id: u64) u64;
@symbol("rt.sys_fresh") fn sys_fresh() u64;
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

export fn haltsys() never = sys_halt();

export fn spawn(path: str) u64 = {
	const p = *(&path: *shdr);
	return sys_spawn(p.data, p.length);
};

export fn alive(id: u64) bool = {
	return sys_alive(id) != 0;
};

export fn cop() void = {
	_ = sys_yield();
};

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

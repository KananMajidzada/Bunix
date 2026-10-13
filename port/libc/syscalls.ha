// Port environment: POSIX syscall wrappers using Bunix userland syscalls

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
@symbol("rt.arg_ptr") let arg_ptr: u64;
@symbol("rt.arg_len") let arg_len: u64;

export fn read(fd: int, buf: *u8, count: size) int = {
	if (fd == 0) {
		let i = 0z;
		for (i < count) {
			const c = sys_readchr();
			if (c == ('\n': u64) || c == ('\r': u64)) {
				*(buf + i) = (c & 0xFF): u8;
				i += 1;
				break;
			};
			*(buf + i) = (c & 0xFF): u8;
			i += 1;
		};
		return i: int;
	};
	return -1;
};

export fn write(fd: int, buf: *const u8, count: size) int = {
	if (fd == 1 || fd == 2) {
		for (let i = 0z; i < count; i += 1) {
			sys_write((buf: uintptr) + i, 1);
		};
		return count: int;
	};
	return -1;
};

export fn open(path: *const u8, flags: int, mode: int) int = {
	return -1;
};

export fn close(fd: int) int = {
	return 0;
};

export fn stat(fd: int, st: *opaque) int = {
	return -1;
};

export fn lseek(fd: int, off: int, whence: int) int = {
	return -1;
};

export fn fork() int = {
	return -1;
};

export fn exec(path: *const u8, argv: *const *const u8, envp: *const *const u8) int = {
	const p = *(&*(&path: *str): *shdr);
	const pid = sys_spawn(p.data, p.length);
	if (pid == ~0u64) {
		return -1;
	};
	for (sys_alive(pid) != 0) {
		sys_yield();
	};
	return 0;
};

export fn waitpid(pid: int, status: *int, options: int) int = {
	for (sys_alive(pid: u64) != 0) {
		sys_yield();
	};
	return pid;
};

export fn exit(code: int) void = {
	_ = code;
};

export fn getpid() int = {
	return 1;
};

export fn brk(addr: *opaque) *opaque = {
	return addr;
};

export fn mmap(addr: *opaque, n: size, prot: int, flags: int, fd: int, off: int) *opaque = {
	return (0: *opaque);
};

export fn munmap(addr: *opaque, n: size) int = {
	return 0;
};

export fn ioctl(fd: int, request: int, arg: *opaque) int = {
	return -1;
};

export fn fcntl(fd: int, cmd: int, arg: int) int = {
	return -1;
};

export fn dup(fd: int) int = {
	return -1;
};

export fn dup2(oldfd: int, newfd: int) int = {
	return -1;
};

export fn pipe(fds: *int) int = {
	return -1;
};

export fn poll(fds: *opaque, nfds: int, timeout: int) int = {
	return 0;
};

export fn select(nfds: int, readfds: *opaque, writefds: *opaque, exceptfds: *opaque, timeout: *opaque) int = {
	return 0;
};

export fn kill(pid: int, sig: int) int = {
	return -1;
};

export fn signal(sig: int, handler: *opaque) *opaque = {
	return (0: *opaque);
};

export fn sigaction(sig: int, act: *opaque, oldact: *opaque) int = {
	return -1;
};
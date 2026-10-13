// Port environment: stdio-like interface

use syscall;

export const STDIN_FILENO: int = 0;
export const STDOUT_FILENO: int = 1;
export const STDERR_FILENO: int = 2;

export const BUFSIZ: size = 8192;

export type FILE = int; // Simplified - just file descriptor

export fn fopen(path: *const u8, mode: *const u8) FILE = {
	let flags = 0;
	if (mode[0] == ('r': u8)) {
		flags = syscall::O_RDONLY;
		if (mode[1] == ('+': u8)) {
			flags = syscall::O_RDWR;
		};
	} else if (mode[0] == ('w': u8)) {
		flags = syscall::O_WRONLY | syscall::O_CREAT | syscall::O_TRUNC;
		if (mode[1] == ('+': u8)) {
			flags = syscall::O_RDWR | syscall::O_CREAT | syscall::O_TRUNC;
		};
	} else if (mode[0] == ('a': u8)) {
		flags = syscall::O_WRONLY | syscall::O_CREAT | syscall::O_APPEND;
		if (mode[1] == ('+': u8)) {
			flags = syscall::O_RDWR | syscall::O_CREAT | syscall::O_APPEND;
		};
	};
	return syscall::open(path, flags, 0o644);
};

export fn fclose(fp: FILE) int = {
	return syscall::close(fp);
};

export fn fread(ptr: *opaque, size: size, nmemb: size, fp: FILE) size = {
	const total = size * nmemb;
	const n = syscall::read(fp, ptr, total);
	if (n < 0) {
		return 0;
	};
	return (n: size) / size;
};

export fn fwrite(ptr: *const opaque, size: size, nmemb: size, fp: FILE) size = {
	const total = size * nmemb;
	const n = syscall::write(fp, ptr, total);
	if (n < 0) {
		return 0;
	};
	return (n: size) / size;
};

export fn fgetc(fp: FILE) int = {
	let ch: u8 = 0;
	const n = syscall::read(fp, &ch, 1);
	if (n <= 0) {
		return -1;
	};
	return (ch: int);
};

export fn fputc(c: int, fp: FILE) int = {
	const ch: u8 = (c: u8);
	const n = syscall::write(fp, &ch, 1);
	if (n < 0) {
		return -1;
	};
	return c;
};

export fn fgets(buf: *u8, n: int, fp: FILE) *u8 = {
	let i = 0;
	for (i < n - 1) {
		const c = fgetc(fp);
		if (c == -1) {
			if (i == 0) {
				return (0: *u8);
			};
			break;
		};
		buf[i] = (c: u8);
		i += 1;
		if (c == ('\n': int)) {
			break;
		};
	};
	buf[i] = 0;
	return buf;
};

export fn fputs(s: *const u8, fp: FILE) int = {
	const len = rt::strlen(s);
	const n = syscall::write(fp, s, len);
	return n;
};

export fn printf(fmt: *const u8, ...) int = {
	// Simplified - just write to stdout
	return syscall::write(STDOUT_FILENO, fmt, rt::strlen(fmt));
};

export fn fprintf(fp: FILE, fmt: *const u8, ...) int = {
	// Simplified
	return syscall::write(fp, fmt, rt::strlen(fmt));
};

export fn sprintf(buf: *u8, fmt: *const u8, ...) int = {
	// Not implemented
	return -1;
};

export fn perror(s: *const u8) void = {
	if (s != (0: *const u8) && s[0] != 0) {
		syscall::write(STDERR_FILENO, s, rt::strlen(s));
		syscall::write(STDERR_FILENO, ": ", 2);
	};
	syscall::write(STDERR_FILENO, "Error\n", 6);
};

export fn fflush(fp: FILE) int = {
	// No-op for unbuffered
	return 0;
};

export fn feof(fp: FILE) int = {
	// Not implemented
	return 0;
};

export fn ferror(fp: FILE) int = {
	// Not implemented
	return 0;
};

export fn rewind(fp: FILE) void = {
	syscall::lseek(fp, 0, 0);
};

export fn fseek(fp: FILE, offset: int, whence: int) int = {
	return syscall::lseek(fp, offset, whence);
};

export fn ftell(fp: FILE) int = {
	return syscall::lseek(fp, 0, 1);
};

export fn setvbuf(fp: FILE, buf: *u8, mode: int, size: size) int = {
	// No-op
	return 0;
};

export fn setbuf(fp: FILE, buf: *u8) void = {
	// No-op
};

export fn tmpfile() FILE = {
	return -1; // Not implemented
};

export fn tmpnam(buf: *u8) *u8 = {
	return (0: *u8); // Not implemented
};

export fn remove(path: *const u8) int = {
	const fd = syscall::open(path, 0, 0);
	if (fd < 0) {
		return -1;
	};
	syscall::close(fd);
	// Would need unlink syscall
	return -1;
};

export fn rename(old: *const u8, new: *const u8) int = {
	// Not implemented
	return -1;
};
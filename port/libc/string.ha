// Port environment: string utilities

export fn strlen(s: *const u8) size = {
	let len = 0z;
	for (s[len] != 0) {
		len += 1;
	};
	return len;
};

export fn strcmp(a: *const u8, b: *const u8) int = {
	let i = 0z;
	for (a[i] != 0 && b[i] != 0) {
		if (a[i] != b[i]) {
			return (a[i]: int) - (b[i]: int);
		};
		i += 1;
	};
	return (a[i]: int) - (b[i]: int);
};

export fn strncmp(a: *const u8, b: *const u8, n: size) int = {
	let i = 0z;
	for (i < n && a[i] != 0 && b[i] != 0) {
		if (a[i] != b[i]) {
			return (a[i]: int) - (b[i]: int);
		};
		i += 1;
	};
	if (i == n) {
		return 0;
	};
	return (a[i]: int) - (b[i]: int);
};

export fn strcpy(dst: *u8, src: *const u8) *u8 = {
	let i = 0z;
	for (src[i] != 0) {
		dst[i] = src[i];
		i += 1;
	};
	dst[i] = 0;
	return dst;
};

export fn strncpy(dst: *u8, src: *const u8, n: size) *u8 = {
	let i = 0z;
	for (i < n && src[i] != 0) {
		dst[i] = src[i];
		i += 1;
	};
	for (i < n) {
		dst[i] = 0;
		i += 1;
	};
	return dst;
};

export fn strcat(dst: *u8, src: *const u8) *u8 = {
	let i = strlen(dst);
	strcpy(dst + i, src);
	return dst;
};

export fn strncat(dst: *u8, src: *const u8, n: size) *u8 = {
	let i = strlen(dst);
	let j = 0z;
	for (j < n && src[j] != 0) {
		dst[i + j] = src[j];
		j += 1;
	};
	dst[i + j] = 0;
	return dst;
};

export fn strchr(s: *const u8, c: int) *u8 = {
	for (let i = 0z; s[i] != 0; i += 1) {
		if (s[i] == (c: u8)) {
			return (s + i: *u8);
		};
	};
	if (c == 0) {
		return (s + strlen(s): *u8);
	};
	return (0: *u8);
};

export fn strrchr(s: *const u8, c: int) *u8 = {
	let last: *u8 = (0: *u8);
	for (let i = 0z; s[i] != 0; i += 1) {
		if (s[i] == (c: u8)) {
			last = (s + i: *u8);
		};
	};
	if (c == 0) {
		return (s + strlen(s): *u8);
	};
	return last;
};

export fn basename(path: *const u8) *u8 = {
	const last = strrchr(path, ('/': int));
	if (last == (0: *u8)) {
		return (path: *u8);
	};
	return last + 1;
};

export fn strlen_slice(s: []u8) size = {
	let len = 0z;
	for (len < len(s) && s[len] != 0) {
		len += 1;
	};
	return len;
};

export fn slice_to_str(s: []u8) str = {
	const len = strlen_slice(s);
	const buf: [256]u8 = [0...];
	rt::memcpy(&buf, s.ptr, len);
	return rt::str_from_slice(buf[..len]);
};

export fn strcat(dst: *u8, src: *const u8) *u8 = {
	let i = strlen(dst);
	strcpy(dst + i, src);
	return dst;
};

export fn strcat_slice(dst: *u8, src: []u8) *u8 = {
	let i = strlen(dst);
	let j = 0z;
	for (j < len(src) && src[j] != 0) {
		dst[i + j] = src[j];
		j += 1;
	};
	dst[i + j] = 0;
	return dst;
};
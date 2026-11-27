// Copy n bytes. The regions must not overlap. A frame is a megabyte, so the
// copy goes a machine word at a time and only the tail is done byte by byte.
export fn memcpy(dest: *opaque, src: *const opaque, n: size) void = {
	let d = dest: uintptr;
	let s = src: uintptr;
	let i = 0z;
	for (i + 8 <= n; i += 8) {
		*((d + i): *u64) = *((s + i): *u64);
	};
	for (i < n) {
		*((d + i): *u8) = *((s + i): *u8);
		i += 1;
	};
};

// Copy n bytes. The regions must not overlap.
export fn memcpy(dest: *opaque, src: *const opaque, n: size) void = {
	let d = dest: *[*]u8;
	let s = src: *[*]u8;
	for (let i = 0z; i < n; i += 1) {
		d[i] = s[i];
	};
};

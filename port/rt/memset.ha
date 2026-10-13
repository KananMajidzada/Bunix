// Set n bytes of dest to val.
export fn memset(dest: *opaque, val: u8, n: size) void = {
	let d = dest: *[*]u8;
	for (let i = 0z; i < n; i += 1) {
		d[i] = val;
	};
};

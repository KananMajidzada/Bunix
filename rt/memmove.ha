// Copy n bytes. The regions may overlap.
export fn memmove(dest: *opaque, src: *const opaque, n: size) void = {
	let d = dest: *[*]u8;
	let s = src: *[*]u8;
	if (d: uintptr == s: uintptr) {
		return;
	};
	if (d: uintptr < s: uintptr) {
		for (let i = 0z; i < n; i += 1) {
			d[i] = s[i];
		};
	} else {
		for (let i = n; i > 0; i -= 1) {
			d[i - 1] = s[i - 1];
		};
	};
};

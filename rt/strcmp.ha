// Strings are not indexable at the language level, so we reach into the
// representation to compare them byte by byte.
type string = struct {
	data: *[*]u8,
	length: size,
	capacity: size,
};

export fn strcmp(a: str, b: str) bool = {
	if (len(a) != len(b)) {
		return false;
	};
	let pa = (&a: *string).data, pb = (&b: *string).data;
	for (let i = 0z; i < len(a); i += 1) {
		if (pa[i] != pb[i]) {
			return false;
		};
	};
	return true;
};

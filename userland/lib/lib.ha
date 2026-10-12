// Helpers the small user programs share: splitting a command line and a
// substring test. Kept here so each program carries one copy.

export fn first_space(b: []u8) size = {
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == (' ': u8)) {
			return i;
		};
	};
	return len(b);
};

export fn contains(hay: []u8, needle: []u8) bool = {
	if (len(needle) == 0) {
		return true;
	};
	if (len(needle) > len(hay)) {
		return false;
	};
	for (let i = 0z; i + len(needle) <= len(hay); i += 1) {
		let ok = true;
		for (let j = 0z; j < len(needle); j += 1) {
			if (hay[i + j] != needle[j]) {
				ok = false;
				break;
			};
		};
		if (ok) {
			return true;
		};
	};
	return false;
};

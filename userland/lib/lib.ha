// Helpers the small user programs share: splitting a command line and a
// substring test. Kept here so each program carries one copy.
//
// A program is handed its arguments, not its own name: the loader takes the
// first word off the line to pick the image to run, and what is left is what
// the program sees. So "sort /tmp/x" arrives as "/tmp/x".

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

export fn str_eq(a: []u8, b: []u8) bool = {
	if (len(a) != len(b)) {
		return false;
	};
	for (let i = 0z; i < len(a); i += 1) {
		if (a[i] != b[i]) {
			return false;
		};
	};
	return true;
};

// The most words a command line is broken into.
export def MAXWORDS: size = 16;

// How long a word can be.
export def WORDLEN: size = 512;

// The words of the last line that was split. The words point here, and not
// into the line, because the quotes are taken off them and the line they
// came from still has the quotes in it.
let wordbuf: [MAXWORDS][WORDLEN]u8 = [[0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...], [0...], [0...], [0...], [0...],
	[0...], [0...], [0...], [0...]];

// Splits a command line into words, on runs of spaces and tabs. A word can
// be in quotes, and the quotes are taken off it, so that a word can hold
// spaces in it. The words point into a buffer of their own, so the line
// does not have to outlive them, and one line can be split over again.
export fn split(b: []u8, words: *[MAXWORDS][]u8) size = {
	let n = 0z;
	let i = 0z;
	let quote = 0u8;
	for (true) {
		// The spaces between the words are not part of a word.
		for (i < len(b) && quote == 0
				&& (b[i] == (' ': u8) || b[i] == ('\t': u8))) {
			i += 1;
		};
		if (i >= len(b) || n >= MAXWORDS) {
			break;
		};
		// The word is put in the buffer of its own, with the quotes off.
		let w = 0z;
		for (true) {
			if (i >= len(b)) {
				break;
			};
			const c = b[i];
			if (quote != 0) {
				// Inside the quotes everything is part of the word,
				// up to the quote that ends them.
				if (c == quote) {
					quote = 0;
					i += 1;
					continue;
				};
				if (w < WORDLEN) {
					wordbuf[n][w] = c;
					w += 1;
				};
				i += 1;
				continue;
			};
			if (c == ('"': u8) || c == ('\'': u8)) {
				quote = c;
				i += 1;
				continue;
			};
			if (c == (' ': u8) || c == ('\t': u8)) {
				break;
			};
			if (w < WORDLEN) {
				wordbuf[n][w] = c;
				w += 1;
			};
			i += 1;
		};
		words[n] = wordbuf[n][..w];
		n += 1;
	};
	return n;
};

// Whether a string starts with a prefix.
export fn has_prefix(b: []u8, p: []u8) bool = {
	if (len(p) > len(b)) {
		return false;
	};
	for (let i = 0z; i < len(p); i += 1) {
		if (b[i] != p[i]) {
			return false;
		};
	};
	return true;
};

// A decimal number, and how much of the string it took. A number that is not
// one takes nothing, so a caller can tell an empty field from a bad one.
export fn number(b: []u8, value: *u64) size = {
	let n = 0u64;
	let i = 0z;
	for (true) {
		if (i >= len(b) || b[i] < ('0': u8) || b[i] > ('9': u8)) {
			break;
		};
		n = n * 10 + ((b[i] - ('0': u8)): u64);
		i += 1;
	};
	if (i == 0) {
		return 0;
	};
	*value = n;
	return i;
};

// Whether a name holds a * in it, and so is a pattern rather than a name.
export fn has_star(b: []u8) bool = {
	for (let i = 0z; i < len(b); i += 1) {
		if (b[i] == ('*': u8)) {
			return true;
		};
	};
	return false;
};

// Whether a name matches a pattern. A * stands for any run of characters.
export fn matches(name: []u8, pat: []u8) bool = {
	const NOSTAR: size = ~0z;
	let ni = 0z;
	let pi = 0z;
	// Where the last * was, and how much of the name it has taken, so the
	// rest of the pattern can be tried again a character further on.
	let star: size = NOSTAR;
	let mark = 0z;
	for (true) {
		// The pattern is used up, and so is the name.
		if (pi == len(pat) && ni == len(name)) {
			return true;
		};
		// A * takes what it can, and gives it back a character at a time.
		if (pi < len(pat) && pat[pi] == ('*': u8)) {
			star = pi;
			mark = ni;
			pi += 1;
			continue;
		};
		if (pi < len(pat) && ni < len(name) && pat[pi] == name[ni]) {
			pi += 1;
			ni += 1;
			continue;
		};
		// The * takes one more character and the rest of the pattern is
		// tried again.
		if (star != NOSTAR && mark < len(name)) {
			mark += 1;
			ni = mark;
			pi = star + 1;
			continue;
		};
		return false;
	};
};

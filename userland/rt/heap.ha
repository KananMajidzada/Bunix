// The slice header handed to ensure and unensure.
export type slice = struct {
	data: nullable *opaque,
	length: size,
	capacity: size,
};

// Every block begins with this header. Once free, next links it to the list.
type block = struct {
	sz: size,
	next: uintptr,
};

def ALIGN: size = 16;
def CHUNK: uintptr = 256 * 1024;
def PAGESZ: uintptr = 4096;

let free_head: uintptr = 0;
let cur: uintptr = 0;
let end: uintptr = 0;

fn alignup(n: size) size = {
	return (n + (ALIGN - 1)) & ~(ALIGN - 1);
};

// Asks the kernel for a fresh run of pages and makes it the bump region.
fn grow(min: uintptr) bool = {
	let want = min;
	if (want < CHUNK) {
		want = CHUNK;
	};
	const pages = ((want + PAGESZ - 1) / PAGESZ): u64;
	const base = page_alloc(pages);
	if (base == 0) {
		return false;
	};
	cur = base;
	end = base + (pages * (PAGESZ: u64)): uintptr;
	return true;
};

export fn malloc(n: size) nullable *opaque = {
	let need = alignup(n);
	if (need == 0) {
		need = ALIGN;
	};

	let prev: uintptr = 0;
	let p = free_head;
	for (p != 0) {
		const b = p: *block;
		if (b.sz >= need) {
			if (prev == 0) {
				free_head = b.next;
			} else {
				const pb = prev: *block;
				pb.next = b.next;
			};
			return (p + size(block)): *opaque;
		};
		prev = p;
		p = b.next;
	};

	const total = (need + size(block)): uintptr;
	if (cur == 0 || cur + total > end) {
		if (!grow(total)) {
			return null;
		};
	};
	const addr = cur;
	const b = addr: *block;
	b.sz = need;
	cur += total;
	return (addr + size(block)): *opaque;
};

export @symbol("rt.free") fn free_(p: nullable *opaque) void = {
	if (p == null) {
		return;
	};
	const addr = p: uintptr - size(block);
	const b = addr: *block;
	b.next = free_head;
	free_head = addr;
};

// Grows or shrinks an allocation in place when it fits.
fn realloc(p: nullable *opaque, n: size) nullable *opaque = {
	const op = match (p) {
	case null =>
		return malloc(n);
	case let q: *opaque =>
		yield q;
	};
	if (n == 0) {
		free_(op);
		return null;
	};
	const addr = op: uintptr - size(block);
	const b = addr: *block;
	if (b.sz >= n) {
		return op;
	};
	const np = match (malloc(n)) {
	case null =>
		return null;
	case let q: *opaque =>
		yield q;
	};
	memcpy(np, op, b.sz);
	free_(op);
	return np;
};

export fn ensure(s: *slice, membsz: size) bool = {
	if (s.capacity >= s.length) {
		return true;
	};
	let cap = s.capacity;
	for (cap < s.length) {
		if (cap == 0) {
			cap = s.length;
		} else {
			cap *= 2;
		};
	};
	const bytes = cap * membsz;
	const data = realloc(s.data, bytes);
	if (data == null) {
		if (bytes == 0) {
			s.data = null;
			s.capacity = 0;
			return true;
		};
		return false;
	};
	s.data = data;
	s.capacity = cap;
	return true;
};

export fn unensure(s: *slice, membsz: size) void = {
	let cap = s.capacity;
	for (cap > s.length) {
		cap /= 2;
	};
	cap *= 2;
	const data = realloc(s.data, cap * membsz);
	if (data != null || cap * membsz == 0) {
		s.data = data;
		s.capacity = cap;
	};
};

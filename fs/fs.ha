use arch;
use bfp;
use block;
use console;
use mem;
use paging;
use rt;
use sched;
use sys;
use user;

// /usr/include alone holds a compiler header set and the C library's, so a
// directory has to be allowed to hold them. These are sized for that tree;
// a node costs roughly 200 bytes plus its children array.
def MAXNODE: size = 512;
def MAXHANDLE: size = 16;
def MAXCHILD: size = 64;
def MAXNS: size = 8;
// A directory listing is the largest thing still gathered into a fixed buffer,
// and a full one of these node names is a little over 2 KiB.
def BUFSZ: size = 4096;
def NOCHILD: size = ~0z;

export type node = struct {
	nam: [32]u8,
	nlen: size,
	isdir: bool,
	nchild: size,
	children: [MAXCHILD]size,
	content: []u8,
	gen: nullable *fn(buf: []u8) size,
	gdsk: nullable *fn(buf: []u8, off: u64, n: size) size,
	writable: bool,
	wdev: nullable *fn(buf: []u8) size,
	wdsk: nullable *fn(data: []u8, off: u64) size,
	wlen: size,
	// A written file's bytes, allocated when it is first written and grown
	// as it fills. A fixed buffer in every node would cap every file at the
	// same small size, and a linker writing an executable needs more room
	// than that.
	wbuf: uintptr,
	wcap: size,
	disk: bool,
	dblock: u32,
	dlen: u32,
};

export type ns = struct {
	root: size,
	inuse: [MAXHANDLE]bool,
	hnode: [MAXHANDLE]size,
	owned: bool,
};

// Handles and node ids both come off the wire in some paths, so every index
// into hnode[] or nodes[] is checked here rather than at each use. A bad value
// is reported once so a caller turning it into a missing file does not turn
// into a wild pointer.
let warned_handle: bool = false;
let warned_node: bool = false;

fn bad_handle(fid: size) void = {
	if (warned_handle) {
		return;
	};
	warned_handle = true;
	console::print("fs: handle out of range: ");
	console::printnum(fid: u64);
	console::println("");
};

fn bad_node(id: size) void = {
	if (warned_node) {
		return;
	};
	warned_node = true;
	console::print("fs: node out of range: ");
	console::printnum(id: u64);
	console::println("");
};

fn hold(s: *ns, fid: size, node: size) void = {
	if (fid >= MAXHANDLE) {
		bad_handle(fid);
		return;
	};
	s.inuse[fid] = true;
	s.hnode[fid] = node;
};

fn hget(s: *ns, fid: size) size = {
	if (fid >= MAXHANDLE) {
		bad_handle(fid);
		return NOCHILD;
	};
	const id = s.hnode[fid];
	if (id >= MAXNODE) {
		bad_node(id);
		return NOCHILD;
	};
	return id;
};

let freehead: size = NOCHILD;
let nextfree: [MAXNODE]size = [0...];
let nused: size = 0;

let nodes: [MAXNODE]node = [node {
	nam = [0...], nlen = 0, isdir = false, nchild = 0, children = [0...],
	content = [], gen = null, gdsk = null, writable = false, wdev = null,
	wdsk = null, wlen = 0, wbuf = 0, wcap = 0, disk = false, dblock = 0, dlen = 0,
}...];
let nnodes: size = 0;
let root: size = 0;
let devroot: size = 0;
let procroot: size = 0;
let usrroot: size = 0;
let binroot: size = 0;
let nss: [MAXNS]ns = [ns {
	root = 0,
	inuse = [false...],
	hnode = [0...],
	owned = false,
}...];

let reqbuf: [BUFSZ]u8 = [0...];
let resbuf: [BUFSZ]u8 = [0...];
let scratch: [BUFSZ]u8 = [0...];
let filebuf: [BUFSZ]u8 = [0...];

def DROOT: u32 = 1;
def DBLK: u32 = 4;
let dnext: u32 = DROOT + 1;
let mntroot: size = 0;

fn mknode(name: str, isdir: bool) size = {
	const id = if (freehead != NOCHILD) {
		const id0 = freehead;
		freehead = nextfree[id0];
		yield id0;
	} else {
		const id0 = nnodes;
		nnodes += 1;
		yield id0;
	};
	const nd = &nodes[id];
	nd.nam = [0...];
	const b = *(&name: *[]u8);
	nd.nlen = len(b);
	for (let i = 0z; i < len(b) && i < 32; i += 1) {
		nd.nam[i] = b[i];
	};
	nd.isdir = isdir;
	nd.nchild = 0;
	nd.children = [0...];
	nd.gen = null;
	nd.gdsk = null;
	nd.writable = false;
	nd.wdev = null;
	nd.wdsk = null;
	nd.wlen = 0;
	nd.wbuf = 0;
	nd.wcap = 0;
	nd.disk = false;
	nd.dblock = 0;
	nd.dlen = 0;
	nused += 1;
	return id;
};

// Makes a file visible at a path that may name subdirectories, so a header
// like "sys/stat.h" lands under a real sys directory rather than as one node
// whose name happens to contain a slash.
fn link_into(parent: size, name: []u8, content: []u8) void = {
	let dir = parent;
	let start = 0z;
	for (let i = 0z; i <= len(name); i += 1) {
		if (i == len(name) || name[i] == ('/': u8)) {
			if (i > start) {
				const seg = name[start..i];
				const last = i == len(name);
				let child = find(dir, seg);
				if (child == NOCHILD) {
					child = mknode(*(&seg: *str), !last);
					link(dir, child);
				};
				if (last) {
					nodes[child].content = content;
				} else {
					dir = child;
				};
			};
			start = i + 1;
		};
	};
};

fn wcopy(dst: uintptr, src: uintptr, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		*((dst + i): *u8) = *((src + i): *u8);
	};
};

fn wzero(p: uintptr, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		*((p + i): *u8) = 0;
	};
};

// Makes room for a written file to reach `need` bytes. Pages are the only
// thing the memory manager hands out, so the size rounds up to one.
fn wreserve(nd: *node, need: size) bool = {
	if (need <= nd.wcap) {
		return true;
	};
	const want = ((need + 4096 - 1) / 4096) * 4096;
	const p = mem::frames_alloc(want / 4096);
	if (p == 0) {
		return false;
	};
	if (nd.wbuf != 0) {
		wcopy(p, nd.wbuf, nd.wlen);
		wzero(p + nd.wcap, want - nd.wcap);
		mem::release(nd.wbuf);
	};
	nd.wbuf = p;
	nd.wcap = want;
	return true;
};

fn free_node(id: size) void = {
	const nd = &nodes[id];
	if (nd.wbuf != 0) {
		mem::release(nd.wbuf);
		nd.wbuf = 0;
		nd.wcap = 0;
	};
	nextfree[id] = freehead;
	freehead = id;
	nused -= 1;
};

fn free_tree(id: size) void = {
	const nd = &nodes[id];
	for (let i = 0z; i < nd.nchild; i += 1) {
		free_tree(nd.children[i]);
	};
	nd.nchild = 0;
	nd.children = [0...];
	free_node(id);
};

fn nodename(id: size) str = {
	return *(&nodes[id].nam[..nodes[id].nlen]: *str);
};

// Refuses a full parent rather than writing past the end of the child array,
// which is what used to take the kernel down at boot once /usr/include outgrew
// the per-directory limit.
fn link(parent: size, child: size) bool = {
	const p = &nodes[parent];
	if (p.nchild >= MAXCHILD) {
		bad_node(parent);
		return false;
	};
	p.children[p.nchild] = child;
	p.nchild += 1;
	return true;
};

fn put_str(buf: []u8, s: str) size = {
	const b = *(&s: *[]u8);
	for (let i = 0z; i < len(b); i += 1) {
		buf[i] = b[i];
	};
	return len(b);
};

fn put_num(buf: []u8, v: u64) size = {
	let tmp: [20]u8 = [0...];
	let i = len(tmp);
	if (v == 0) {
		i -= 1;
		tmp[i] = '0': u8;
	} else {
		let n = v;
		for (n > 0) {
			i -= 1;
			tmp[i] = ((n % 10): u8) + ('0': u8);
			n /= 10;
		};
	};
	const k = len(tmp) - i;
	for (let j = 0z; j < k; j += 1) {
		buf[j] = tmp[i + j];
	};
	return k;
};

def ARTPAD: size = 15;

fn version_info(buf: []u8, n: size, line: size) size = {
	let m = n;
	switch (line) {
	case 0 =>
		m += put_str(buf[m..], "bunix@bunix");
	case 1 =>
		m += put_str(buf[m..], "-----------");
	case 2 =>
		m += put_str(buf[m..], "OS: ");
		m += put_str(buf[m..], sys::NAME);
		buf[m] = ' ': u8;
		m += 1;
		m += put_str(buf[m..], sys::VERSION);
	case 3 =>
		m += put_str(buf[m..], "Kernel: ");
		m += put_str(buf[m..], sys::NAME);
		buf[m] = ' ': u8;
		m += 1;
		m += put_str(buf[m..], sys::VERSION);
	case 4 =>
		m += put_str(buf[m..], "Uptime: ");
		m += put_num(buf[m..], arch::seconds());
		buf[m] = 's': u8;
		m += 1;
	case 5 =>
		m += put_str(buf[m..], "Memory: ");
		m += put_num(buf[m..], mem::free_frames());
		m += put_str(buf[m..], " free of ");
		m += put_num(buf[m..], mem::total_frames());
	case 6 =>
		m += put_str(buf[m..], "Threads: ");
		m += put_num(buf[m..], sched::live(): u64);
	case 7 =>
		m += put_str(buf[m..], "Shell: ush");
	case 8 =>
		m += put_str(buf[m..], "Init: /sh");
	case => void;
	};
	return m;
};

fn gen_version(buf: []u8) size = {
	let n = 0z;
	for (let i = 0z; i < len(sys::ART); i += 1) {
		const a = *(&sys::ART[i]: *[]u8);
		for (let j = 0z; j < len(a); j += 1) {
			buf[n] = a[j];
			n += 1;
		};
		let col = len(a);
		for (col < ARTPAD) {
			buf[n] = ' ': u8;
			n += 1;
			col += 1;
		};
		n = version_info(buf, n, i);
		buf[n] = '\n': u8;
		n += 1;
	};
	return n;
};

fn gen_uptime(buf: []u8) size = {
	let n = put_num(buf, arch::seconds());
	buf[n] = '\n': u8;
	n += 1;
	return n;
};

fn gen_mem(buf: []u8) size = {
	let n = put_str(buf, "frames free ");
	n += put_num(buf[n..], mem::free_frames());
	n += put_str(buf[n..], " of ");
	n += put_num(buf[n..], mem::total_frames());
	buf[n] = '\n': u8;
	n += 1;
	return n;
};

fn gen_self(buf: []u8) size = {
	let n = put_str(buf, "pid ");
	n += put_num(buf[n..], sched::running());
	buf[n] = '\n': u8;
	n += 1;
	return n;
};

fn gen_threads(buf: []u8) size = {
	let n = put_str(buf, "threads ");
	n += put_num(buf[n..], sched::live(): u64);
	buf[n] = '\n': u8;
	n += 1;
	return n;
};

fn gen_files(buf: []u8) size = {
	let n = put_str(buf, "nodes in use ");
	n += put_num(buf[n..], nused: u64);
	n += put_str(buf[n..], " of ");
	n += put_num(buf[n..], MAXNODE: u64);
	buf[n] = '\n': u8;
	n += 1;
	return n;
};

def LSZ: u64 = 512;

fn disk_gen(buf: []u8, off: u64, n: size) size = {
	let got = 0z;
	let s = off / LSZ;
	let p = (off % LSZ): size;
	let local: [512]u8 = [0...];
	for (got < n && s < block::nsect()) {
		if (!block::read(s, local[..])) {
			break;
		};
		const take = if (512 - p < n - got) 512 - p else n - got;
		for (let j = 0z; j < take; j += 1) {
			buf[got + j] = local[p + j];
		};
		got += take;
		s += 1;
		p = 0;
	};
	return got;
};

fn disk_wdev(data: []u8, off: u64) size = {
	let wrote = 0z;
	let s = off / LSZ;
	let p = (off % LSZ): size;
	let local: [512]u8 = [0...];
	for (wrote < len(data) && s < block::nsect()) {
		if (!block::read(s, local[..])) {
			break;
		};
		const take = if (512 - p < len(data) - wrote) 512 - p else len(data) - wrote;
		for (let j = 0z; j < take; j += 1) {
			local[p + j] = data[wrote + j];
		};
		if (!block::write(s, local[..])) {
			break;
		};
		wrote += take;
		s += 1;
		p = 0;
	};
	return wrote;
};

// Byte-order helpers for the on-disk format. The superblock lives in sector 0:
// magic "BUNX2" at byte 0, the root directory block at byte 8, the next free
// block at byte 12. A directory block is a count byte followed by 42-byte
// entries: type, name length, name, data block, length in bytes.
fn wle(b: []u8, off: size, v: u32) void = {
	b[off] = v: u8;
	b[off + 1] = (v >> 8): u8;
	b[off + 2] = (v >> 16): u8;
	b[off + 3] = (v >> 24): u8;
};

fn rle(b: []u8, off: size) u32 = {
	return (b[off]: u32) | ((b[off + 1]: u32) << 8)
		| ((b[off + 2]: u32) << 16) | ((b[off + 3]: u32) << 24);
};

fn sb_write() void = {
	let b: [512]u8 = [0...];
	b[0] = 'B': u8;
	b[1] = 'U': u8;
	b[2] = 'N': u8;
	b[3] = 'X': u8;
	b[4] = '2': u8;
	wle(b, 8, DROOT);
	wle(b, 12, dnext);
	block::write(0, b[..]);
};

fn sb_read() bool = {
	let b: [512]u8 = [0...];
	if (!block::read(0, b[..])) {
		return false;
	};
	if (b[0] != 'B' || b[1] != 'U' || b[2] != 'N' || b[3] != 'X' || b[4] != '2') {
		return false;
	};
	dnext = rle(b, 12);
	return true;
};

fn dalloc() u32 = {
	const blk = dnext;
	dnext += 1;
	sb_write();
	return blk;
};

fn dfind_parent(id: size) size = {
	for (let p = 0z; p < nnodes; p += 1) {
		const nd = &nodes[p];
		if (!nd.isdir) {
			continue;
		};
		for (let i = 0z; i < nd.nchild; i += 1) {
			if (nd.children[i] == id) {
				return p;
			};
		};
	};
	return NOCHILD;
};

fn dsave_dir(id: size) void = {
	const nd = &nodes[id];
	let b: [512]u8 = [0...];
	b[0] = nd.nchild: u8;
	for (let i = 0z; i < nd.nchild; i += 1) {
		const c = nd.children[i];
		const cn = &nodes[c];
		const off = 1 + i * 42;
		b[off] = if (cn.isdir) 2 else 1;
		b[off + 1] = cn.nlen: u8;
		for (let j = 0z; j < cn.nlen && j < 32; j += 1) {
			b[off + 2 + j] = cn.nam[j];
		};
		for (let j = cn.nlen; j < 32; j += 1) {
			b[off + 2 + j] = 0;
		};
		wle(b, off + 34, cn.dblock);
		wle(b, off + 38, cn.dlen);
	};
	block::write(nd.dblock: u64, b[..]);
};

fn dpull(id: size) void = {
	const nd = &nodes[id];
	if (nd.dlen == 0) {
		return;
	};
	let loc: [512]u8 = [0...];
	let got = 0z;
	let todo = nd.dlen: size;
	let blk = nd.dblock;
	for (todo > 0) {
		if (!block::read(blk: u64, loc[..])) {
			break;
		};
		const take = if (512z < todo) 512z else todo;
		if (!wreserve(nd, got + take)) {
			break;
		};
		for (let i = 0z; i < take; i += 1) {
			*((nd.wbuf + (got + i)): *u8) = loc[i];
		};
		got += take;
		todo -= take;
		blk += 1;
	};
	nd.wlen = got;
};

fn dload_dir(id: size, blk: u32) void = {
	let b: [512]u8 = [0...];
	if (!block::read(blk: u64, b[..])) {
		return;
	};
	const cnt = b[0]: size;
	for (let i = 0z; i < cnt; i += 1) {
		const off = 1 + i * 42;
		const isdir = b[off] == 2;
		const nlen = b[off + 1]: size;
		const nm = b[off + 2..off + 2 + nlen];
		const child = mknode(*(&nm: *str), isdir);
		nodes[child].disk = true;
		nodes[child].dblock = rle(b, off + 34);
		nodes[child].dlen = rle(b, off + 38);
		if (isdir) {
			link(id, child);
			dload_dir(child, nodes[child].dblock);
		} else {
			nodes[child].writable = true;
			dpull(child);
			link(id, child);
		};
	};
};

fn dstore(id: size) void = {
	const nd = &nodes[id];
	if (nd.dblock == 0 && nd.wlen > 0) {
		nd.dblock = dnext;
		dnext += DBLK;
		sb_write();
	};
	if (nd.dblock != 0) {
		let b: [512]u8 = [0...];
		let pos = 0z;
		const last = nd.dblock + DBLK;
		for (let blk = nd.dblock; blk < last; blk += 1) {
			for (let j = 0z; j < 512; j += 1) {
				b[j] = 0;
			};
			const take = if (512z < nd.wlen - pos) 512z else nd.wlen - pos;
			for (let j = 0z; j < take; j += 1) {
				b[j] = *((nd.wbuf + (pos + j)): *u8);
			};
			block::write(blk: u64, b[..]);
			pos += take;
			if (pos >= nd.wlen) {
				break;
			};
		};
		nd.dlen = nd.wlen: u32;
		dsave_dir(dfind_parent(id));
	};
};

fn dmount() void = {
	if (!block::present_drive()) {
		return;
	};
	mntroot = mknode("mnt", true);
	nodes[mntroot].disk = true;
	nodes[mntroot].dblock = DROOT;
	link(root, mntroot);
	if (sb_read()) {
		dload_dir(mntroot, DROOT);
	} else {
		sb_write();
		dsave_dir(mntroot);
	};
};

export fn init() void = {
	root = mknode("/", true);
	const dev = mknode("dev", true);
	const proc = mknode("proc", true);
	devroot = dev;
	procroot = proc;
	link(root, dev);
	link(root, proc);

	const hello = mknode("hello", false);
	let hellos: str = "hello from the Bunix File Protocol\n";
	nodes[hello].content = *(&hellos: *[]u8);
	link(root, hello);

	// /tmp belongs to every namespace, shared or private: a ported program
	// expects somewhere writable to exist without creating it first.
	link(root, mknode("tmp", true));

	// /usr/include holds the compiler's own headers, and /usr/src the examples
	// it is expected to be able to compile. Both are tables built at compile
	// time by tools/embed.py.
	const usr = mknode("usr", true);
	link(root, usr);
	usrroot = usr;
	const inc = mknode("include", true);
	link(usr, inc);
	for (let i = 0z; i < len(user::headers); i += 1) {
		link_into(inc, *(&user::headers[i].nam: *[]u8), user::headers[i].bytes);
	};

	// Create /usr/lib and populate with CRT startup files
	const lib = mknode("lib", true);
	link(usr, lib);
	for (let i = 0z; i < len(user::crts); i += 1) {
		const id = mknode(*(&user::crts[i].nam: *str), false);
		nodes[id].content = user::crts[i].bytes;
		link(lib, id);
	};
	for (let i = 0z; i < len(user::libcs); i += 1) {
		const id = mknode(*(&user::libcs[i].nam: *str), false);
		nodes[id].content = user::libcs[i].bytes;
		link(lib, id);
	};

	const share = mknode("src", true);
	link(usr, share);
	for (let i = 0z; i < len(user::srcs); i += 1) {
		const c = mknode(*(&user::srcs[i].nam: *str), false);
		nodes[c].content = user::srcs[i].bytes;
		link(share, c);
	};

	const bin = mknode("bin", true);
	link(root, bin);
	binroot = bin;
	// One /bin entry per program image, taken from the same table the loader
	// reads, so the names here can never drift from what the shell can run.
	for (let i = 0z; i < len(user::programs); i += 1) {
		const nm = *(&user::programs[i].nam: *str);
		const id = mknode(nm, false);
		nodes[id].content = [];
		link(bin, id);
	};

	link(dev, mknode("null", false));

	const cons = mknode("cons", false);
	nodes[cons].wdev = &console::write;
	link(dev, cons);

	const note = mknode("note", false);
	nodes[note].writable = true;
	link(dev, note);

	const disk = mknode("disk", false);
	nodes[disk].gdsk = &disk_gen;
	nodes[disk].wdsk = &disk_wdev;
	link(dev, disk);

	const version = mknode("version", false);
	nodes[version].gen = &gen_version;
	link(proc, version);

	const uptime = mknode("uptime", false);
	nodes[uptime].gen = &gen_uptime;
	link(proc, uptime);

	const memfile = mknode("mem", false);
	nodes[memfile].gen = &gen_mem;
	link(proc, memfile);

	const threads = mknode("threads", false);
	nodes[threads].gen = &gen_threads;
	link(proc, threads);

	const self = mknode("self", false);
	nodes[self].gen = &gen_self;
	link(proc, self);

	const files = mknode("files", false);
	nodes[files].gen = &gen_files;
	link(proc, files);

	dmount();
	nss[0].root = root;
	sched::reap_hook = &ns_reap;
};

export fn cur() *ns = {
	const id = sched::running(): size;
	if (id >= MAXNS) {
		return &nss[0];
	};
	return &nss[id];
};

// A fresh namespace keeps the shared /dev and /proc as binds and adds its own
// writable /tmp; everything else the process makes stays private to it.
fn ns_root_make() size = {
	const r = mknode("/", true);
	link(r, devroot);
	link(r, procroot);
	link(r, usrroot);
	link(r, binroot);
	link(r, mknode("tmp", true));
	return r;
};

export fn ns_install(id: size, fresh: bool) void = {
	if (id >= MAXNS) {
		return;
	};
	nss[id] = ns {
		root = if (fresh) ns_root_make() else root,
		inuse = [false...],
		hnode = [0...],
		owned = fresh,
	};
};

// Frees the private nodes of a dead process; the shared binds stay put.
export fn ns_reap(id: size) void = {
	if (id >= MAXNS || !nss[id].owned) {
		return;
	};
	const r = nss[id].root;
	const nd = &nodes[r];
	for (let i = 0z; i < nd.nchild; i += 1) {
		const c = nd.children[i];
		if (c != devroot && c != procroot) {
			free_tree(c);
		};
	};
	free_node(r);
	nss[id] = ns {
		root = 0,
		inuse = [false...],
		hnode = [0...],
		owned = false,
	};
};

fn name_eq(a: str, b: []u8) bool = {
	const ab = *(&a: *[]u8);
	if (len(ab) != len(b)) {
		return false;
	};
	for (let i = 0z; i < len(b); i += 1) {
		if (ab[i] != b[i]) {
			return false;
		};
	};
	return true;
};

fn find(parent: size, name: []u8) size = {
	if (parent >= MAXNODE) {
		bad_node(parent);
		return NOCHILD;
	};
	const nd = &nodes[parent];
	if (!nd.isdir) {
		return NOCHILD;
	};
	for (let i = 0z; i < nd.nchild; i += 1) {
		const c = nd.children[i];
		if (name_eq(nodename(c), name)) {
			return c;
		};
	};
	return NOCHILD;
};

fn unlink(id: size) void = {
	for (let p = 0z; p < nnodes; p += 1) {
		const nd = &nodes[p];
		if (!nd.isdir) {
			continue;
		};
		for (let i = 0z; i < nd.nchild; i += 1) {
			if (nd.children[i] == id) {
				for (let j = i; j + 1 < nd.nchild; j += 1) {
					nd.children[j] = nd.children[j + 1];
				};
				nd.nchild -= 1;
				return;
			};
		};
	};
};

fn kind_of(id: size) u8 = {
	if (id >= MAXNODE) {
		bad_node(id);
		return 0;
	};
	return if (nodes[id].isdir) bfp::IDDIR else 0;
};

fn listdir(id: size) []u8 = {
	let n = 0z;
	if (id >= MAXNODE) {
		bad_node(id);
		let empty: []u8 = [];
		return empty;
	};
	const nd = &nodes[id];
	for (let i = 0z; i < nd.nchild; i += 1) {
		n += put_str(scratch[n..], nodename(nd.children[i]));
		scratch[n] = '\n': u8;
		n += 1;
	};
	return scratch[..n];
};

export fn list_path(path: str) []u8 = {
	const id = lookup(*(&path: *[]u8));
	if (id == NOCHILD) {
		let empty: []u8 = [];
		return empty;
	};
	return listdir(id);
};

fn put_ident(w: *bfp::writer, id: size, typ: u8) void = {
	bfp::write_ident(w, id: u64, typ);
};

fn do_proto(w: *bfp::writer, r: *bfp::reader) void = {
	const msize = bfp::r_u32(r);
	_ = bfp::r_bytes(r);
	bfp::w_u32(w, msize);
	bfp::w_str(w, bfp::REVISION);
};

fn do_attach(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	_ = bfp::r_u32(r);
	_ = bfp::r_bytes(r);
	_ = bfp::r_bytes(r);
	hold(s, fid: size, s.root);
	put_ident(w, s.root, bfp::IDDIR);
};

fn do_walk(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const newfid = bfp::r_u32(r);
	const count = bfp::r_u16(r);
	if (count == 1) {
		const name = bfp::r_bytes(r);
		const child = find(hget(s, fid: size), name);
		if (child != NOCHILD) {
			hold(s, newfid: size, child);
			bfp::w_u16(w, 1);
			put_ident(w, child, kind_of(child));
			return;
		};
	};
	bfp::w_u16(w, 0);
};

fn do_open(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	_ = bfp::r_u8(r);
	const id = hget(s, fid: size);
	put_ident(w, id, kind_of(id));
	bfp::w_u32(w, 0);
};

fn do_read(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const off = bfp::r_u64(r);
	const count = bfp::r_u32(r): size;
	// Keep the whole reply inside the response buffer, framing included.
	const cap = if (count > BUFSZ - 64) BUFSZ - 64 else count;
	const id = hget(s, fid: size);
	let data: []u8 = [];
	if (nodes[id].isdir) {
		data = listdir(id);
	} else if (nodes[id].writable) {
		data = (nodes[id].wbuf: *[_]u8)[..nodes[id].wlen];
	} else {
		match (nodes[id].gdsk) {
		case null =>
			match (nodes[id].gen) {
			case null =>
				data = nodes[id].content;
			case let g: *fn(buf: []u8) size =>
				const k = g(scratch[..]);
				data = scratch[..k];
			};
		case let g: *fn(buf: []u8, off: u64, n: size) size =>
			data = scratch[..g(scratch[..], off, cap)];
		};
	};
	let n = len(data);
	if (n > cap) {
		n = cap;
	};
	bfp::w_u32(w, n: u32);
	bfp::w_bytes(w, data[..n]);
};

fn do_clunk(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r): size;
	if (fid >= MAXHANDLE) {
		bad_handle(fid);
		return;
	};
	s.inuse[fid] = false;
};

fn do_write(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const off = bfp::r_u64(r): size;
	const data = bfp::r_bytes(r);
	const id = hget(s, fid: size);
	if (id >= MAXNODE) {
		bfp::w_u32(w, 0);
		return;
	};
	match (nodes[id].wdev) {
	case null => void;
	case let f: *fn(buf: []u8) size =>
		_ = f(data);
		bfp::w_u32(w, len(data): u32);
		return;
	};
	match (nodes[id].wdsk) {
	case null => void;
	case let f: *fn(data: []u8, off: u64) size =>
		bfp::w_u32(w, f(data, off): u32);
		return;
	};
	if (!nodes[id].writable) {
		bfp::w_u32(w, 0);
		return;
	};
	const nd = &nodes[id];
	let n = len(data);
	if (!wreserve(nd, off + n)) {
		bfp::w_u32(w, 0);
		return;
	};
	for (let i = 0z; i < n; i += 1) {
		*((nd.wbuf + (off + i)): *u8) = data[i];
	};
	if (off + n > nd.wlen) {
		nd.wlen = off + n;
	};
	if (nodes[id].disk) {
		dstore(id);
	};
	bfp::w_u32(w, n: u32);
};

fn do_create(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const name = bfp::r_bytes(r);
	const isdir = bfp::r_u8(r) != 0;
	const nd = &nodes[hget(s, fid: size)];
	if (!nd.isdir || nd.nchild >= MAXCHILD || nnodes >= MAXNODE) {
		put_ident(w, bfp::NOHANDLE: size, 0);
		return;
	};
	if (len(name) == 0 || len(name) > 31) {
		put_ident(w, bfp::NOHANDLE: size, 0);
		return;
	};
	if (find(hget(s, fid: size), name) != NOCHILD) {
		put_ident(w, bfp::NOHANDLE: size, 0);
		return;
	};
	const parent = hget(s, fid: size);
	const child = mknode(*(&name: *str), isdir);
	nodes[child].writable = !isdir;
	link(parent, child);
	if (nodes[parent].disk) {
		nodes[child].disk = true;
		if (isdir) {
			nodes[child].dblock = dalloc();
			dsave_dir(child);
		};
		dsave_dir(parent);
	};
	put_ident(w, child, kind_of(child));
};

fn do_remove(s: *ns, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const id = hget(s, fid: size);
	if (id == s.root || (nodes[id].isdir && nodes[id].nchild > 0)) {
		bfp::w_u32(w, 0);
		return;
	};
	const parent = dfind_parent(id);
	const wasdisk = nodes[id].disk;
	unlink(id);
	free_node(id);
	if (wasdisk && parent != NOCHILD) {
		dsave_dir(parent);
	};
	bfp::w_u32(w, 1);
};

fn do_error(w: *bfp::writer, tag: u16) void = {
	w.off = 0;
	bfp::begin(w, bfp::RERROR, tag);
	bfp::w_str(w, "unsupported");
};

fn handle(s: *ns, in: []u8, out: []u8) size = {
	const h = bfp::parse_header(in);
	let r = bfp::reader { buf = in, off = bfp::HDR };
	let w = bfp::writer { buf = out, off = 0 };
	bfp::begin(&w, h.typ + 1, h.tag);
	switch (h.typ) {
	case bfp::TPROTO =>
		do_proto(&w, &r);
	case bfp::TATTACH =>
		do_attach(s, &w, &r);
	case bfp::TWALK =>
		do_walk(s, &w, &r);
	case bfp::TOPEN =>
		do_open(s, &w, &r);
	case bfp::TREAD =>
		do_read(s, &w, &r);
	case bfp::TWRITE =>
		do_write(s, &w, &r);
	case bfp::TCREATE =>
		do_create(s, &w, &r);
	case bfp::TREMOVE =>
		do_remove(s, &w, &r);
	case bfp::TCLUNK =>
		do_clunk(s, &w, &r);
	case =>
		do_error(&w, h.tag);
	};
	return bfp::finish(&w);
};

fn send(s: *ns, w: *bfp::writer) []u8 = {
	const n = bfp::finish(w);
	const rn = handle(s, w.buf[..n], resbuf[..]);
	return resbuf[..rn];
};

fn proto(s: *ns) void = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TPROTO, bfp::NOTAG);
	bfp::w_u32(&w, BUFSZ: u32);
	bfp::w_str(&w, bfp::REVISION);
	_ = send(s, &w);
};

fn attach(s: *ns) u32 = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TATTACH, 0);
	bfp::w_u32(&w, 0);
	bfp::w_u32(&w, bfp::NOHANDLE);
	bfp::w_str(&w, "bunix");
	bfp::w_str(&w, "");
	_ = send(s, &w);
	return 0;
};

fn walk1(s: *ns, fid: u32, newfid: u32, name: []u8) bool = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TWALK, 1);
	bfp::w_u32(&w, fid);
	bfp::w_u32(&w, newfid);
	bfp::w_u16(&w, 1);
	bfp::w_u16(&w, len(name): u16);
	bfp::w_bytes(&w, name);
	const resp = send(s, &w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	return bfp::r_u16(&r) == 1;
};

fn walkpath(s: *ns, path: []u8) u32 = {
	proto(s);
	let fid = attach(s);
	let nextfid: u32 = 1;
	let start = 0z;
	for (let i = 0z; i <= len(path); i += 1) {
		if (i == len(path) || path[i] == ('/': u8)) {
			if (i > start) {
				// Every step takes a fresh handle, so a deep path can run the
				// table out.
				if (nextfid >= MAXHANDLE) {
					bad_handle(nextfid: size);
					return bfp::NOHANDLE;
				};
				const name = path[start..i];
				if (!walk1(s, fid, nextfid, name)) {
					return bfp::NOHANDLE;
				};
				fid = nextfid;
				nextfid += 1;
			};
			start = i + 1;
		};
	};
	return fid;
};

fn read_all(s: *ns, fid: u32) []u8 = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TOPEN, 2);
	bfp::w_u32(&w, fid);
	bfp::w_u8(&w, 0);
	_ = send(s, &w);

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TREAD, 3);
	bfp::w_u32(&w, fid);
	bfp::w_u64(&w, 0);
	bfp::w_u32(&w, BUFSZ: u32);
	const resp = send(s, &w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	const count = bfp::r_u32(&r): size;
	for (let i = 0z; i < count; i += 1) {
		filebuf[i] = bfp::r_u8(&r);
	};

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TCLUNK, 4);
	bfp::w_u32(&w, fid);
	_ = send(s, &w);

	return filebuf[..count];
};

// A path resolves straight to a node id. The old route sent a string of wire
// messages (proto, attach, one walk per component) and ended at a 2 KiB
// message buffer, which capped every read at that size and was the single
// biggest cost in the compiler's file handling. Nothing here needs the wire:
// the "server" is this same file.
fn lookup(path: []u8) size = {
	let id = cur().root;
	let start = 0z;
	for (let i = 0z; i <= len(path); i += 1) {
		if (i == len(path) || path[i] == ('/': u8)) {
			if (i > start) {
				id = find(id, path[start..i]);
				if (id == NOCHILD) {
					return NOCHILD;
				};
			};
			start = i + 1;
		};
	};
	return id;
};

fn copy_in(dst: uintptr, src: []u8, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		*((dst + i): *u8) = src[i];
	};
};

fn copy_out(dst: []u8, src: uintptr, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		dst[i] = *((src + i): *u8);
	};
};

fn copy_bytes(dst: []u8, src: []u8, n: size) void = {
	for (let i = 0z; i < n; i += 1) {
		dst[i] = src[i];
	};
};

// Hand a node's bytes to dest, filling at most len(dest) of it. A regular
// file yields its contents; a directory yields its name listing.
fn read_node(id: size, dest: []u8) size = {
	const nd = &nodes[id];
	if (nd.isdir) {
		const l = listdir(id);
		let n = len(l);
		if (n > len(dest)) {
			n = len(dest);
		};
		copy_bytes(dest, l, n);
		return n;
	};
	if (nd.writable) {
		let n = nd.wlen;
		if (n > len(dest)) {
			n = len(dest);
		};
		copy_out(dest, nd.wbuf, n);
		return n;
	};
	match (nd.gdsk) {
	case let g: *fn(buf: []u8, off: u64, n: size) size =>
		return g(dest, 0, len(dest));
	case null => void;
	};
	match (nd.gen) {
	case let g: *fn(buf: []u8) size =>
		return g(dest);
	case null => void;
	};
	let n = len(nd.content);
	if (n > len(dest)) {
		n = len(dest);
	};
	copy_bytes(dest, nd.content, n);
	return n;
};

export fn read(path: str, dest: []u8) size = {
	const id = lookup(*(&path: *[]u8));
	if (id == NOCHILD) {
		return 0;
	};
	return read_node(id, dest);
};

export type filestat = struct {
	length: u64,
	isdir: bool,
};

// Size and type without moving any bytes. The old route to a stat was to read
// the whole file and count, which made every stat(2) cost as much as a read.
export fn stat(path: str, out: *filestat) bool = {
	const id = lookup(*(&path: *[]u8));
	if (id == NOCHILD) {
		return false;
	};
	const nd = &nodes[id];
	out.isdir = nd.isdir;
	out.length = 0;
	if (!nd.isdir) {
		if (nd.writable) {
			out.length = nd.wlen: u64;
		} else if (nd.gdsk == null && nd.gen == null) {
			out.length = len(nd.content): u64;
		};
	};
	return true;
};

export fn cat(path: str) []u8 = {
	const id = lookup(*(&path: *[]u8));
	if (id == NOCHILD) {
		return filebuf[..0];
	};
	const n = read_node(id, filebuf[..]);
	return filebuf[..n];
};

export fn exists(path: str) bool = {
	return lookup(*(&path: *[]u8)) != NOCHILD;
};

export fn write_file(path: str, data: []u8) size = {
	const p = *(&path: *[]u8);
	let id = lookup(p);
	if (id == NOCHILD) {
		// A plain "write this file" makes the file when it is not there yet.
		// Without this the first write of a new file simply vanished.
		if (!create(path, false)) {
			return 0;
		};
		id = lookup(p);
		if (id == NOCHILD) {
			return 0;
		};
	};
	const nd = &nodes[id];
	match (nd.wdev) {
	case let f: *fn(buf: []u8) size =>
		return f(data);
	case null => void;
	};
	match (nd.wdsk) {
	case let f: *fn(data: []u8, off: u64) size =>
		return f(data, 0);
	case null => void;
	};
	if (!nd.writable) {
		return 0;
	};
	if (!wreserve(nd, len(data))) {
		return 0;
	};
	copy_in(nd.wbuf, data, len(data));
	// What was just written is the whole file; a longer previous version must
	// not leave a tail behind.
	nd.wlen = len(data);
	if (nd.disk) {
		dstore(id);
	};
	return len(data);
};

export fn create(path: str, isdir: bool) bool = {
	const p = *(&path: *[]u8);
	let slash = NOCHILD;
	for (let i = 0z; i < len(p); i += 1) {
		if (p[i] == ('/': u8)) {
			slash = i;
		};
	};
	if (slash == NOCHILD) {
		return false;
	};
	const parent = if (slash == 0) "/" else *(&p[..slash]: *str);
	const base = p[slash + 1..];
	if (len(base) == 0 || len(base) > 31) {
		return false;
	};
	const pid = lookup(*(&parent: *[]u8));
	if (pid == NOCHILD || !nodes[pid].isdir) {
		return false;
	};
	if (nodes[pid].nchild >= MAXCHILD || nnodes >= MAXNODE) {
		return false;
	};
	if (find(pid, base) != NOCHILD) {
		return false;
	};
	const child = mknode(*(&base: *str), isdir);
	nodes[child].writable = !isdir;
	link(pid, child);
	if (nodes[pid].disk) {
		nodes[child].disk = true;
		if (isdir) {
			nodes[child].dblock = dalloc();
			dsave_dir(child);
		};
		dsave_dir(pid);
	};
	return true;
};

export fn remove(path: str) bool = {
	const id = lookup(*(&path: *[]u8));
	if (id == NOCHILD || id == cur().root) {
		return false;
	};
	if (nodes[id].isdir && nodes[id].nchild > 0) {
		return false;
	};
	const parent = dfind_parent(id);
	const wasdisk = nodes[id].disk;
	unlink(id);
	free_node(id);
	if (wasdisk && parent != NOCHILD) {
		dsave_dir(parent);
	};
	return true;
};

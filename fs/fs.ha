use arch;
use bfp;
use console;
use mem;
use sched;
use sys;

def MAXNODE: size = 64;
def MAXHANDLE: size = 16;
def MAXCHILD: size = 8;
def BUFSZ: size = 2048;
def NOCHILD: size = ~0z;

export type node = struct {
	nam: [32]u8,
	nlen: size,
	isdir: bool,
	nchild: size,
	children: [MAXCHILD]size,
	content: str,
	gen: nullable *fn(buf: []u8) size,
	writable: bool,
	wdev: nullable *fn(buf: []u8) size,
	wlen: size,
	wbuf: [BUFSZ]u8,
};

type slot = struct {
	inuse: bool,
	node: size,
};

type server = struct {
	handles: [MAXHANDLE]slot,
};

let nodes: [MAXNODE]node = [node {
	nam = [0...], nlen = 0, isdir = false, nchild = 0, children = [0...],
	content = "", gen = null, writable = false, wdev = null,
	wlen = 0, wbuf = [0...],
}...];
let nnodes: size = 0;
let root: size = 0;
let srv = server {
	handles = [slot { inuse = false, node = 0 }...],
};

let reqbuf: [BUFSZ]u8 = [0...];
let resbuf: [BUFSZ]u8 = [0...];
let scratch: [BUFSZ]u8 = [0...];
let filebuf: [BUFSZ]u8 = [0...];

fn mknode(name: str, isdir: bool) size = {
	const id = nnodes;
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
	nd.content = "";
	nd.gen = null;
	nd.writable = false;
	nd.wdev = null;
	nd.wlen = 0;
	nd.wbuf = [0...];
	nnodes += 1;
	return id;
};

fn nodename(id: size) str = {
	return *(&nodes[id].nam[..nodes[id].nlen]: *str);
};

fn link(parent: size, child: size) void = {
	const p = &nodes[parent];
	p.children[p.nchild] = child;
	p.nchild += 1;
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

fn gen_version(buf: []u8) size = {
	let n = put_str(buf, sys::NAME);
	buf[n] = ' ': u8;
	n += 1;
	n += put_str(buf[n..], sys::VERSION);
	buf[n] = '\n': u8;
	n += 1;
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

fn gen_threads(buf: []u8) size = {
	let n = put_str(buf, "threads ");
	n += put_num(buf[n..], sched::live(): u64);
	buf[n] = '\n': u8;
	n += 1;
	return n;
};

export fn init() void = {
	root = mknode("/", true);
	const dev = mknode("dev", true);
	const proc = mknode("proc", true);
	link(root, dev);
	link(root, proc);

	const hello = mknode("hello", false);
	nodes[hello].content = "hello from the Bunix File Protocol\n";
	link(root, hello);

	link(dev, mknode("null", false));

	const cons = mknode("cons", false);
	nodes[cons].wdev = &console::write;
	link(dev, cons);

	const note = mknode("note", false);
	nodes[note].writable = true;
	link(dev, note);

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
	return if (nodes[id].isdir) bfp::IDDIR else 0;
};

fn listdir(id: size) []u8 = {
	let n = 0z;
	const nd = &nodes[id];
	for (let i = 0z; i < nd.nchild; i += 1) {
		n += put_str(scratch[n..], nodename(nd.children[i]));
		scratch[n] = '\n': u8;
		n += 1;
	};
	return scratch[..n];
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

fn do_attach(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	_ = bfp::r_u32(r);
	_ = bfp::r_bytes(r);
	_ = bfp::r_bytes(r);
	s.handles[fid: size] = slot { inuse = true, node = root };
	put_ident(w, root, bfp::IDDIR);
};

fn do_walk(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const newfid = bfp::r_u32(r);
	const count = bfp::r_u16(r);
	if (count == 1) {
		const name = bfp::r_bytes(r);
		const child = find(s.handles[fid: size].node, name);
		if (child != NOCHILD) {
			s.handles[newfid: size] = slot { inuse = true, node = child };
			bfp::w_u16(w, 1);
			put_ident(w, child, kind_of(child));
			return;
		};
	};
	bfp::w_u16(w, 0);
};

fn do_open(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	_ = bfp::r_u8(r);
	const id = s.handles[fid: size].node;
	put_ident(w, id, kind_of(id));
	bfp::w_u32(w, 0);
};

fn do_read(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	_ = bfp::r_u64(r);
	const count = bfp::r_u32(r): size;
	const id = s.handles[fid: size].node;
	let data: []u8 = [];
	if (nodes[id].isdir) {
		data = listdir(id);
	} else if (nodes[id].writable) {
		data = nodes[id].wbuf[..nodes[id].wlen];
	} else {
		match (nodes[id].gen) {
		case null =>
			data = *(&nodes[id].content: *[]u8);
		case let g: *fn(buf: []u8) size =>
			const k = g(scratch[..]);
			data = scratch[..k];
		};
	};
	let n = len(data);
	if (n > count) {
		n = count;
	};
	bfp::w_u32(w, n: u32);
	bfp::w_bytes(w, data[..n]);
};

fn do_clunk(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	s.handles[fid: size].inuse = false;
};

fn do_write(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const off = bfp::r_u64(r): size;
	const data = bfp::r_bytes(r);
	const id = s.handles[fid: size].node;
	match (nodes[id].wdev) {
	case null => void;
	case let f: *fn(buf: []u8) size =>
		_ = f(data);
		bfp::w_u32(w, len(data): u32);
		return;
	};
	if (!nodes[id].writable || off >= BUFSZ) {
		bfp::w_u32(w, 0);
		return;
	};
	const nd = &nodes[id];
	let n = len(data);
	if (off + n > BUFSZ) {
		n = BUFSZ - off;
	};
	for (let i = 0z; i < n; i += 1) {
		nd.wbuf[off + i] = data[i];
	};
	if (off + n > nd.wlen) {
		nd.wlen = off + n;
	};
	bfp::w_u32(w, n: u32);
};

fn do_create(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const name = bfp::r_bytes(r);
	const isdir = bfp::r_u8(r) != 0;
	const nd = &nodes[s.handles[fid: size].node];
	if (!nd.isdir || nd.nchild >= MAXCHILD || nnodes >= MAXNODE) {
		put_ident(w, bfp::NOHANDLE: size, 0);
		return;
	};
	if (len(name) == 0 || len(name) > 31) {
		put_ident(w, bfp::NOHANDLE: size, 0);
		return;
	};
	if (find(s.handles[fid: size].node, name) != NOCHILD) {
		put_ident(w, bfp::NOHANDLE: size, 0);
		return;
	};
	const parent = s.handles[fid: size].node;
	const child = mknode(*(&name: *str), isdir);
	nodes[child].writable = !isdir;
	link(parent, child);
	put_ident(w, child, kind_of(child));
};

fn do_remove(s: *server, w: *bfp::writer, r: *bfp::reader) void = {
	const fid = bfp::r_u32(r);
	const id = s.handles[fid: size].node;
	if (id == root || (nodes[id].isdir && nodes[id].nchild > 0)) {
		bfp::w_u32(w, 0);
		return;
	};
	unlink(id);
	const nd = &nodes[id];
	nd.nam = [0...];
	nd.nlen = 0;
	nd.isdir = false;
	nd.nchild = 0;
	nd.content = "";
	nd.gen = null;
	nd.writable = false;
	nd.wdev = null;
	nd.wlen = 0;
	bfp::w_u32(w, 1);
};

fn do_error(w: *bfp::writer, tag: u16) void = {
	w.off = 0;
	bfp::begin(w, bfp::RERROR, tag);
	bfp::w_str(w, "unsupported");
};

fn handle(s: *server, in: []u8, out: []u8) size = {
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

fn send(w: *bfp::writer) []u8 = {
	const n = bfp::finish(w);
	const rn = handle(&srv, w.buf[..n], resbuf[..]);
	return resbuf[..rn];
};

fn proto() void = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TPROTO, bfp::NOTAG);
	bfp::w_u32(&w, BUFSZ: u32);
	bfp::w_str(&w, bfp::REVISION);
	_ = send(&w);
};

fn attach() u32 = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TATTACH, 0);
	bfp::w_u32(&w, 0);
	bfp::w_u32(&w, bfp::NOHANDLE);
	bfp::w_str(&w, "bunix");
	bfp::w_str(&w, "");
	_ = send(&w);
	return 0;
};

fn walk1(fid: u32, newfid: u32, name: []u8) bool = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TWALK, 1);
	bfp::w_u32(&w, fid);
	bfp::w_u32(&w, newfid);
	bfp::w_u16(&w, 1);
	bfp::w_u16(&w, len(name): u16);
	bfp::w_bytes(&w, name);
	const resp = send(&w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	return bfp::r_u16(&r) == 1;
};

fn walkpath(path: []u8) u32 = {
	proto();
	let fid = attach();
	let nextfid: u32 = 1;
	let start = 0z;
	for (let i = 0z; i <= len(path); i += 1) {
		if (i == len(path) || path[i] == ('/': u8)) {
			if (i > start) {
				const name = path[start..i];
				if (!walk1(fid, nextfid, name)) {
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

fn read_all(fid: u32) []u8 = {
	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TOPEN, 2);
	bfp::w_u32(&w, fid);
	bfp::w_u8(&w, 0);
	_ = send(&w);

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TREAD, 3);
	bfp::w_u32(&w, fid);
	bfp::w_u64(&w, 0);
	bfp::w_u32(&w, BUFSZ: u32);
	const resp = send(&w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	const count = bfp::r_u32(&r): size;
	for (let i = 0z; i < count; i += 1) {
		filebuf[i] = bfp::r_u8(&r);
	};

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TCLUNK, 4);
	bfp::w_u32(&w, fid);
	_ = send(&w);

	return filebuf[..count];
};

export fn cat(path: str) []u8 = {
	const p = *(&path: *[]u8);
	const fid = walkpath(p);
	if (fid == bfp::NOHANDLE) {
		return filebuf[..0];
	};
	return read_all(fid);
};

export fn exists(path: str) bool = {
	const p = *(&path: *[]u8);
	return walkpath(p) != bfp::NOHANDLE;
};

export fn write_file(path: str, data: []u8) size = {
	const p = *(&path: *[]u8);
	const fid = walkpath(p);
	if (fid == bfp::NOHANDLE) {
		return 0;
	};

	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TOPEN, 5);
	bfp::w_u32(&w, fid);
	bfp::w_u8(&w, 1);
	_ = send(&w);

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TWRITE, 6);
	bfp::w_u32(&w, fid);
	bfp::w_u64(&w, 0);
	bfp::w_u16(&w, len(data): u16);
	bfp::w_bytes(&w, data);
	const resp = send(&w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	const n = bfp::r_u32(&r): size;

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TCLUNK, 7);
	bfp::w_u32(&w, fid);
	_ = send(&w);

	return n;
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
	if (len(base) == 0) {
		return false;
	};
	const fid = walkpath(*(&parent: *[]u8));
	if (fid == bfp::NOHANDLE) {
		return false;
	};

	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TCREATE, 8);
	bfp::w_u32(&w, fid);
	bfp::w_u16(&w, len(base): u16);
	bfp::w_bytes(&w, base);
	bfp::w_u8(&w, if (isdir) 1 else 0);
	const resp = send(&w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	_ = bfp::r_u8(&r);
	_ = bfp::r_u32(&r);
	const nid = bfp::r_u64(&r);

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TCLUNK, 9);
	bfp::w_u32(&w, fid);
	_ = send(&w);

	return nid != (bfp::NOHANDLE: u64);
};

export fn remove(path: str) bool = {
	const p = *(&path: *[]u8);
	const fid = walkpath(p);
	if (fid == bfp::NOHANDLE) {
		return false;
	};

	let w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TREMOVE, 8);
	bfp::w_u32(&w, fid);
	const resp = send(&w);
	let r = bfp::reader { buf = resp, off = bfp::HDR };
	const ok = bfp::r_u32(&r);

	w = bfp::writer { buf = reqbuf[..], off = 0 };
	bfp::begin(&w, bfp::TCLUNK, 9);
	bfp::w_u32(&w, fid);
	_ = send(&w);

	return ok != 0;
};

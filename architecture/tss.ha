@symbol("tss") let tss_mem: [104]u8;
@symbol("gdt64_tss") let gdt_tss: [16]u8;

const RSP0: size = 4;
const IOMAP: size = 102;

fn put16(off: size, v: u16) void = {
	let p = &tss_mem[off]: *u16;
	*p = v;
};

export fn tss_init() void = {
	const base = &tss_mem: uintptr;
	const limit = 103u64;

	gdt_tss[0] = (limit & 0xFF): u8;
	gdt_tss[1] = ((limit >> 8) & 0xFF): u8;
	gdt_tss[2] = (base & 0xFF): u8;
	gdt_tss[3] = ((base >> 8) & 0xFF): u8;
	gdt_tss[4] = ((base >> 16) & 0xFF): u8;
	gdt_tss[5] = 0x89;
	gdt_tss[6] = ((limit >> 16) & 0x0F): u8;
	gdt_tss[7] = ((base >> 24) & 0xFF): u8;
	gdt_tss[8] = ((base >> 32) & 0xFF): u8;
	gdt_tss[9] = ((base >> 40) & 0xFF): u8;
	gdt_tss[10] = ((base >> 48) & 0xFF): u8;
	gdt_tss[11] = ((base >> 56) & 0xFF): u8;

	put16(IOMAP, 104);
	ltr(0x28);
};

export fn set_rsp0(addr: uintptr) void = {
	let p = &tss_mem[RSP0]: *u64;
	*p = addr: u64;
};

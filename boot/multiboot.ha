// Multiboot 1 information, as left in memory by the boot loader.

export def MAGIC: u32 = 0x2BADB002;

export def FLAG_MEMORY: u32 = 1 << 0;
export def FLAG_MMAP: u32 = 1 << 6;
export def FLAG_VIDEO: u32 = 1 << 12;

export type info = struct {
	flags: u32,
	mem_lower: u32,
	mem_upper: u32,
	boot_device: u32,
	cmdline: u32,
	mods_count: u32,
	mods_addr: u32,
	syms: [4]u32,
	mmap_length: u32,
	mmap_addr: u32,
	drives_length: u32,
	drives_addr: u32,
	config_table: u32,
	boot_loader_name: u32,
	apm_table: u32,
	vbe_control_info: u32,
	vbe_mode_info: u32,
	vbe_mode: u16,
	vbe_interface_seg: u16,
	vbe_interface_off: u16,
	vbe_interface_len: u16,
	framebuffer_addr: u64,
	framebuffer_pitch: u32,
	framebuffer_width: u32,
	framebuffer_height: u32,
	framebuffer_bpp: u8,
	framebuffer_type: u8,
};

export type mmap_entry = struct @packed {
	sz: u32,
	base: u64,
	length: u64,
	typ: u32,
};

export def TYPE_AVAILABLE: u32 = 1;

export fn at(addr: uintptr) *info = {
	return (addr: *info);
};

export fn available(mb: *info) u64 = {
	if ((mb.flags & FLAG_MMAP) == 0) {
		return 0;
	};
	let total = 0u64;
	let p = mb.mmap_addr: uintptr;
	const end = p + (mb.mmap_length: uintptr);
	for (p < end) {
		const e = p: *mmap_entry;
		if (e.typ == TYPE_AVAILABLE) {
			total += e.length;
		};
		p += (e.sz + 4): uintptr;
	};
	return total;
};

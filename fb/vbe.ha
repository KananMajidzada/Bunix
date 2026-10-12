use arch;
use paging;

// When the bootloader gives no framebuffer, switch the VGA card ourselves: the
// Bochs VBE (dispi) interface on QEMU's stdvga sets the mode, and PCI config
// space tells us where the linear framebuffer lives.

def VBE_INDEX: u16 = 0x01CE;
def VBE_DATA: u16 = 0x01CF;

def PCI_ADDR: u16 = 0xCF8;
def PCI_DATA: u16 = 0xCFC;

def MODE_W: size = 1024;
def MODE_H: size = 768;

fn vbereg(idx: u16, val: u16) void = {
	arch::outw(VBE_INDEX, idx);
	arch::outw(VBE_DATA, val);
};

fn pci_addr(bus: u32, dev: u32, func: u32, reg: u32) u32 = {
	return 0x80000000u32 | (bus << 16) | (dev << 11) | (func << 8) | (reg & 0xFC);
};

fn pci_read(bus: u32, dev: u32, func: u32, reg: u32) u32 = {
	arch::outl(PCI_ADDR, pci_addr(bus, dev, func, reg));
	return arch::inl(PCI_DATA);
};

fn pci_write(bus: u32, dev: u32, func: u32, reg: u32, val: u32) void = {
	arch::outl(PCI_ADDR, pci_addr(bus, dev, func, reg));
	arch::outl(PCI_DATA, val);
};

export fn vbe() bool = {
	// The display class device's first BAR is the framebuffer window.
	for (let d = 0u32; d < 32; d += 1) {
		const vid = pci_read(0, d, 0, 0x00) & 0xFFFF;
		if (vid == 0 || vid == 0xFFFF) {
			continue;
		};
		if ((pci_read(0, d, 0, 0x08) >> 16) != 0x0300) {
			continue;
		};
		const raw = pci_read(0, d, 0, 0x10);
		if ((raw & 1) != 0) {
			return false;
		};
		const base = raw & 0xFFFFFFF0;
		if (base == 0) {
			return false;
		};
		// A BAR reports its size when all its address bits are set.
		pci_write(0, d, 0, 0x10, 0xFFFFFFFF);
		const mask = pci_read(0, d, 0, 0x10) & 0xFFFFFFF0;
		pci_write(0, d, 0, 0x10, raw);
		let bytes = (~mask) + 1;
		if (bytes < 0x200000) {
			bytes = 0x200000;
		};
		paging::map_fb(base: uintptr, bytes: u64);

		vbereg(0x00, 0xB0C0);
		vbereg(0x01, MODE_W: u16);
		vbereg(0x02, MODE_H: u16);
		vbereg(0x03, 32);
		vbereg(0x04, 0x41);
		addr = base: uintptr;
		pitch = MODE_W * 4;
		fbw = MODE_W;
		fbh = MODE_H;
		shadow_init();
		return true;
	};
	return false;
};

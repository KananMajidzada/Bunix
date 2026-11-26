use architecture;

// A Sound Blaster 16: the card that gives the machine more than one pitch
// at a time. It plays 8-bit and 16-bit PCM from a buffer the ISA DMA
// controller copies to it, one block at a time. A block finishing raises
// the card's interrupt, which is when audio.ha hands it the next one.
//
// The card is found by resetting its DSP and asking for the version. The
// interrupt, DMA channel and mixer settings are read back from the card
// rather than assumed, so a machine that was given another line still
// works. Only the conventional base addresses are tried; a card far from
// them is not found, and the machine is simply quiet.
//
// The DMA buffer must sit in the first 16 MiB, because that is all the ISA
// DMA controller can reach. audio.ha owns that buffer.

def RESET: u16 = 0x06;
def MIX_ADDR: u16 = 0x04;
def MIX_DATA: u16 = 0x05;
def READ_DATA: u16 = 0x0A;
def WRITE_DATA: u16 = 0x0C;
def READ_STATUS: u16 = 0x0E;
def IRQ16_ACK: u16 = 0x0F;

def MIN_RATE: u32 = 5000;
def MAX_RATE: u32 = 45000;

let base: u16 = 0x220;
let found: bool = false;
let irqline: u8 = 5;
let dma_low: u8 = 1;
let dma_high: u8 = 5;
let version: u16 = 0;

export fn present() bool = found;
export fn irq() u8 = irqline;
export fn dma8() u8 = dma_low;
export fn dma16() u8 = dma_high;
export fn base_port() u16 = base;
export fn dsp_version() u16 = version;

fn wait_write() bool = {
	for (let i = 0u64; i < 100000; i += 1) {
		if ((architecture::inb(base + WRITE_DATA) & 0x80) == 0) {
			return true;
		};
	};
	return false;
};

// A command or a parameter, once the DSP says it can take one.
fn wr(v: u8) bool = {
	if (!wait_write()) {
		return false;
	};
	architecture::outb(base + WRITE_DATA, v);
	return true;
};

fn rd(v: *u8) bool = {
	for (let i = 0u64; i < 100000; i += 1) {
		if ((architecture::inb(base + READ_STATUS) & 0x80) != 0) {
			*v = architecture::inb(base + READ_DATA);
			return true;
		};
	};
	return false;
};

fn mix_write(reg: u8, val: u8) void = {
	architecture::outb(base + MIX_ADDR, reg);
	architecture::io_wait();
	architecture::outb(base + MIX_DATA, val);
	architecture::io_wait();
};

fn mix_read(reg: u8) u8 = {
	architecture::outb(base + MIX_ADDR, reg);
	architecture::io_wait();
	return architecture::inb(base + MIX_DATA);
};

fn reset() bool = {
	architecture::outb(base + RESET, 1);
	for (let i = 0u64; i < 64; i += 1) {
		architecture::io_wait();
	};
	architecture::outb(base + RESET, 0);
	for (let i = 0u64; i < 100000; i += 1) {
		if ((architecture::inb(base + READ_STATUS) & 0x80) != 0) {
			return architecture::inb(base + READ_DATA) == 0xAA;
		};
	};
	return false;
};

// The two half-bytes of the version. The first byte the card gives back is
// the high one: the DSP hands its output over in the reverse of the order
// it queued it.
fn read_version() u16 = {
	if (!wr(0xE1)) {
		return 0;
	};
	let hi = 0u8;
	let lo = 0u8;
	if (!rd(&hi) || !rd(&lo)) {
		return 0;
	};
	return (hi: u16 << 8) | lo: u16;
};

fn irq_of(magic: u8) u8 = {
	switch (magic) {
	case 1 =>
		return 9;
	case 2 =>
		return 5;
	case 4 =>
		return 7;
	case 8 =>
		return 10;
	case =>
		return 5;
	};
};

// The lowest set bit of each nibble: the mixer packs the 8-bit DMA channel
// in the low half and the 16-bit channel in the high half.
fn channel_of(mask: u8, shift: u8) u8 = {
	const m = (mask >> shift) & 0x0F;
	for (let i = 0u8; i < 4; i += 1) {
		if ((m & (1: u8 << i)) != 0) {
			return i;
		};
	};
	return 0xFF;
};

fn probe(b: u16) bool = {
	base = b;
	if (!reset()) {
		return false;
	};
	version = read_version();
	// The mixer is readable only on a card that really answered, so the
	// settings come from it rather than from a guess.
	const magic = mix_read(0x80);
	irqline = irq_of(magic);
	const low = channel_of(mix_read(0x81), 0);
	const high = channel_of(mix_read(0x81), 4);
	if (low < 4) {
		dma_low = low;
	};
	if (high >= 5 && high <= 7) {
		dma_high = high;
	};
	return true;
};

export fn init() bool = {
	const bases: [4]u16 = [0x220, 0x240, 0x260, 0x280];
	for (let i = 0z; i < len(bases); i += 1) {
		if (probe(bases[i])) {
			found = true;
			break;
		};
	};
	if (!found) {
		return false;
	};
	// Full volume on the mixer: the program that writes samples decides
	// how loud they are, and a second volume control only makes it quiet.
	mix_write(0x22, 0xFF);
	mix_write(0x04, 0xFF);
	wr(0xD1);
	return true;
};

export fn stop() void = {
	if (!found) {
		return;
	};
	// Halt either DMA engine that may still be running, then close the
	// speaker. A single-cycle transfer has already stopped by itself,
	// but a program may stop a tune in the middle.
	_ = wr(0xD0);
	_ = wr(0xD5);
	_ = wr(0xD3);
	dma_mask(dma_low, true);
	dma_mask(dma_high, true);
};

export fn ack() void = {
	if (!found) {
		return;
	};
	// Reading either interrupt acknowledge port also clears that IRQ.
	_ = architecture::inb(base + READ_STATUS);
	_ = architecture::inb(base + IRQ16_ACK);
};

fn dma_mask(ch: u8, mask: bool) void = {
	if (ch < 4) {
		const v = if (mask) (0x04: u8) + ch else ch;
		architecture::outb(0x0A, v);
	} else {
		const v = if (mask) (0x04: u8) + (ch - 4) else (ch - 4);
		architecture::outb(0xD4, v);
	};
};

fn dma_flip(ch: u8) void = {
	if (ch < 4) {
		architecture::outb(0x0C, 0);
	} else {
		architecture::outb(0xD8, 0);
	};
};

// Single transfer, address incrementing, memory read: the direction that
// copies the buffer to the card.
fn dma_mode(ch: u8) void = {
	if (ch < 4) {
		architecture::outb(0x0B, 0x48 + ch);
	} else {
		architecture::outb(0xD6, 0x48 + (ch - 4));
	};
};

fn dma_page(ch: u8) u16 = {
	if (ch == 0) {
		return 0x87;
	} else if (ch == 1) {
		return 0x83;
	} else if (ch == 2) {
		return 0x81;
	} else if (ch == 3) {
		return 0x82;
	} else if (ch == 5) {
		return 0x8B;
	} else if (ch == 6) {
		return 0x89;
	};
	return 0x8A;
};

fn dma_addr(ch: u8) u16 = {
	if (ch == 0) {
		return 0x00;
	} else if (ch == 1) {
		return 0x02;
	} else if (ch == 2) {
		return 0x04;
	} else if (ch == 3) {
		return 0x06;
	} else if (ch == 5) {
		return 0xC4;
	} else if (ch == 6) {
		return 0xC8;
	};
	return 0xCC;
};

fn dma_count(ch: u8) u16 = {
	if (ch == 0) {
		return 0x01;
	} else if (ch == 1) {
		return 0x03;
	} else if (ch == 2) {
		return 0x05;
	} else if (ch == 3) {
		return 0x07;
	} else if (ch == 5) {
		return 0xC6;
	} else if (ch == 6) {
		return 0xCA;
	};
	return 0xCE;
};

fn bytes_per_frame(channels: u8, bits: u8) size = {
	let f = if (bits == 16) 2z else 1z;
	if (channels == 2) {
		f = f * 2;
	};
	return f;
};

fn program_dma(ch: u8, addr: uintptr, bytes: size, wide: bool) void = {
	dma_mask(ch, true);
	dma_flip(ch);
	dma_mode(ch);
	// The 16-bit controller counts words, not bytes, and its address
	// register holds the address with the low bit shifted away. The page
	// register still names the 64 KiB page the bytes live in.
	let a = addr;
	let n = bytes;
	if (wide) {
		a = a >> 1;
		n /= 2;
	};
	if (n == 0) {
		n = 1;
	};
	const count = n - 1;
	architecture::outb(dma_page(ch), ((addr >> 16) & 0xFF): u8);
	architecture::outb(dma_addr(ch), (a & 0xFF): u8);
	architecture::outb(dma_addr(ch), ((a >> 8) & 0xFF): u8);
	architecture::outb(dma_count(ch), (count & 0xFF): u8);
	architecture::outb(dma_count(ch), ((count >> 8) & 0xFF): u8);
	dma_mask(ch, false);
};

// Plays bytes of PCM from addr. The format is signed 16-bit when bits is
// 16, unsigned 8-bit otherwise, with one or two channels. The call returns
// as soon as the card has been told to start; audio.ha waits for the
// interrupt that says the block is over.
export fn play(addr: uintptr, bytes: size, rate: u32, channels: u8, bits: u8) bool = {
	if (!found || bytes == 0) {
		return false;
	};
	let r = rate;
	if (r < MIN_RATE) {
		r = MIN_RATE;
	} else if (r > MAX_RATE) {
		r = MAX_RATE;
	};
	const wide = bits == 16;
	const frame = bytes_per_frame(channels, bits);
	let n = bytes;
	if (n % frame != 0) {
		n -= n % frame;
	};
	if (n == 0) {
		return false;
	};
	let frames = n / frame;
	if (frames > 65536) {
		frames = 65536;
	};
	const ch = if (wide) dma_high else dma_low;
	program_dma(ch, addr, frames * frame, wide);
	if (!wr(0x41)) {
		return false;
	};
	if (!wr(((r >> 8) & 0xFF): u8) || !wr((r & 0xFF): u8)) {
		return false;
	};
	// Speaker on before the transfer: a card that was left muted by a
	// previous block would otherwise play it silently.
	if (!wr(0xD1)) {
		return false;
	};
	// The type byte: bit 5 stereo, bit 4 signed. All 16-bit samples are
	// signed and all 8-bit samples are unsigned, which is the format the
	// rest of the system writes.
	let kind = 0u8;
	if (wide) {
		kind |= 0x10;
	};
	if (channels == 2) {
		kind |= 0x20;
	};
	const cmd = if (wide) 0xB0u8 else 0xC0u8;
	if (!wr(cmd) || !wr(kind)) {
		return false;
	};
	const count = (frames - 1): u16;
	if (!wr((count & 0xFF): u8) || !wr(((count >> 8) & 0xFF): u8)) {
		return false;
	};
	return true;
};

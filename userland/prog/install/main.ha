use rt;

// install -- copy the running system's disk image to another drive.
//
// This is what installing from a USB stick to an internal disk means: the
// system is already running from one disk, and the user points at another
// and says "make it like this one". The source is the disk the kernel
// booted from, which is known because the boot loader passed it. The
// target is chosen by the user from the list of drives the system found.

export fn main() void = {
	const src = rt::boot_drive();
	rt::print("source drive: ");
	rt::printnum(src);
	rt::println("");

	// List the drives we can see.
	rt::println("drives:");
	let found = false;
	for (let i = 0z; i < 4; i += 1) {
		if (i == src) {
			continue;		// the source is already the system disk
		};
		if (!rt::block_drive_present(i)) {
			continue;
		};
		found = true;
		const sz = rt::block_drive_sectors(i);
		const mb = sz * 512 / (1024 * 1024);
		rt::print("  ");
		rt::printnum(i);
		rt::print(": ");
		rt::printnum(mb);
		rt::println(" MiB");
	};
	if (!found) {
		rt::println("no target drives found");
		rt::halt();
	};

	rt::print("target drive: ");
	// For now hardcode the first non-source drive. A real installer
	// would read a keystroke here.
	let tgt = 0z;
	for (let i = 0z; i < 4; i += 1) {
		if (i != src && rt::block_drive_present(i)) {
			tgt = i;
			break;
		};
	};
	rt::printnum(tgt);
	rt::println("");

	const src_sectors = rt::block_drive_sectors(src);
	const tgt_sectors = rt::block_drive_sectors(tgt);
	if (src_sectors > tgt_sectors) {
		rt::println("target too small");
		rt::halt();
	};

	rt::print("copying ");
	rt::printnum(src_sectors);
	rt::println(" sectors...");

	let ok = 0z;
	let buf: [512]u8 = [0...];
	for (let s = 0z; s < src_sectors: size; s += 1) {
		if (rt::block_read(src, s, buf[..]) != 0) {
			if (rt::block_write(tgt, s, buf[..]) != 0) {
				ok += 1;
			} else {
				rt::println("write failed at sector ");
				rt::printnum(s);
				rt::halt();
			};
		} else {
			rt::println("read failed at sector ");
			rt::printnum(s);
			rt::halt();
		};
		if ((s % 100) == 0) {
			rt::printnum(s);
			rt::print("/");
			rt::printnum(src_sectors);
			rt::putc('\r');
		};
	};
	rt::println("done.                    ");
	rt::printnum(ok);
	rt::println(" sectors copied.");
	rt::rebootsys();
};
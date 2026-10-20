/* Bunix's own bootloader.
 *
 * This is the other half of rt/start.s. That file expects to be entered by
 * something that has already put the machine in 32-bit protected mode and
 * left a Multiboot 1 information structure in %ebx with 0x2BADB002 in %eax.
 * GRUB does that; so did QEMU's -kernel, before the image became a flat
 * binary. This does it too, so the system can be started from a disk with
 * nothing else installed on it.
 *
 * It runs in real mode, which is what a BIOS hands a boot sector over in.
 * Three things have to happen before the kernel can take over: a graphics
 * mode has to be set, because the kernel draws windows and a text mode has
 * no pixels; the memory map has to be read, because the frame allocator
 * needs to know which addresses exist; and the CPU has to be lifted into
 * protected mode with a GDT, because the kernel is 32-bit code.
 *
 * The output is a Multiboot 1 structure, built here rather than borrowed,
 * so the kernel has one boot protocol to understand instead of two. Only
 * the fields the kernel reads are filled in, and the flags word says which
 * of them mean anything, which is what the kernel checks.
 *
 * The payload is read to 0x100000 by this loader's own disk driver, running
 * in 32-bit mode, and entered from there. It cannot be read with a BIOS call:
 * a BIOS call writes through a real-mode segment, so it can only reach the
 * first megabyte, and the kernel is linked above that. By the time the read
 * happens the CPU is already in protected mode, which is also why the disk
 * driver here talks to the controller directly. The payload's length and
 * where to jump are patched into the image by the build script, which is the
 * only part of this that knows anything about the kernel.
 *
 * The layout rule that matters, and that is easy to get wrong twice: a
 * BIOS loads exactly one sector, so the boot sector can only call what is
 * inside its own 512 bytes. Anything it calls -- the print routine, the
 * disk reader -- has to live there, not in the sectors after it, because
 * those are still unread at the moment of the call. The same goes for any
 * variable read before the loader has been read in, which is why
 * loader_sectors sits here rather than with the other build-patched words.
 */

.set LOADER_SEG, 0x07E0		/* read the rest of the loader in at 0x7E00 */

/* ------------------------------------------------------------------------ */
/* The boot sector: the 512 bytes the BIOS loads and jumps to.              */
/* ------------------------------------------------------------------------ */

.section .bootsect, "ax"
.code16
.global boot_start
boot_start:
	cli
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw $0x7C00, %sp
	sti
	cld

	/* Nothing may be printed before this line. The BIOS leaves the drive
	 * it booted from in %dl and nothing else remembers it, so it has to
	 * be saved before the first thing that uses %dx for its own
	 * purposes, which serial output does. */
	movb %dl, boot_drive

	movw $bs_msg_start, %si
	call bs_print

	/* Conventional and extended memory. The frame allocator will not
	 * hand out anything below 1 MiB, so these only have to be roughly
	 * right for the two lines the kernel prints at boot. */
	clc
	int $0x12
	movw %ax, mem_lower_kb

	movl $0xE801, %eax
	int $0x15
	jc bs_mem_done
	/* Some BIOSes return the answer in %ax/%bx and some in %cx/%dx;
	 * when %ax is non-zero the first pair is the real one. */
	testw %ax, %ax
	jnz bs_mem_got
	movw %cx, %ax
	movw %dx, %bx
bs_mem_got:
	/* %ax counts kilobytes between 1 MiB and 16 MiB and %bx counts
	 * 64 KiB blocks above 16 MiB. Only the first is a number of
	 * kilobytes, so the second is scaled before the two are added;
	 * using %ax alone reports fifteen megabytes on a machine with
	 * a quarter of a gigabyte in it. */
	movzwl %ax, %eax
	movzwl %bx, %ecx
	shll $6, %ecx
	addl %ecx, %eax
	movl %eax, mem_upper_kb
bs_mem_done:

	/* Read the rest of the loader to directly above this sector, then
	 * jump into it. The loader is longer than one sector, so this is the
	 * only way to reach the code that does the real work. */
	movw $LOADER_SEG, %ax
	movw %ax, %es
	xorw %bx, %bx
	movl $1, read_lba		/* LBA 1: the sector after the boot sector */
	movl loader_sectors, %ecx
	decl %ecx
bs_load_loader:
	testl %ecx, %ecx
	jz bs_into_loader
	pushl %ecx
	call read_sector
	popl %ecx
	jc bs_load_failed
	/* %es stays where it is and %bx is the offset within it, and an
	 * offset in a segment is counted in bytes, not in paragraphs. So
	 * this is 512, not 512/16: dividing here would advance by 32 bytes
	 * a sector and leave the loader's second sector written over its
	 * first, which looks like the loader starting and then stopping. */
	addw $512, %bx
	incl read_lba
	decl %ecx
	jmp bs_load_loader

bs_into_loader:
	ljmp $LOADER_SEG, $0

bs_load_failed:
	movw $bs_msg_nodisk, %si
	call bs_print
	jmp bs_hang

bs_hang:
	cli
1:	hlt
	jmp 1b

/* Print the string at %si. A copy of the loader's routine rather than a
 * call into it, because at the point the boot sector first prints the
 * loader has not been read in and the copy there is still garbage. */
bs_print:
	pushw %ax
	pushw %dx
1:	lodsb
	testb %al, %al
	jz 2f
	movb %al, %ah
	movb $0xF8, %dl
	movb $0x03, %dh
	movb %ah, %al
	outb %al, %dx
	jmp 1b
2:	popw %dx
	popw %ax
	ret

/* Read the sector whose 1-based number is in read_lba, into %es:%bx.
 *
 * The BIOS takes a head, cylinder and sector rather than a flat number, so
 * this is where the arithmetic lives: 63 sectors to a track and 2 heads to
 * a cylinder, which is what every BIOS since 1984 assumes. The geometry is
 * not queried because a bootloader that gets it wrong does not boot, and
 * this one only ever reads from the very start of the disk, where the
 * assumption holds.
 *
 * The destination is %bx, which is also one of the registers the BIOS
 * wants, so it is parked in %si while the sector number is worked out.
 * Using %bx as scratch here is an easy mistake and a fatal one: the BIOS
 * would be told to read to whatever the cylinder arithmetic left behind. */
read_sector:
	pushl %eax
	pushl %edx
	pushl %ecx
	pushl %esi
	movw %bx, %si			/* keep the destination */
	movl read_lba, %eax
	xorl %edx, %edx
	movl $63, %ecx
	divl %ecx			/* %eax = track, %edx = sector - 1 */
	incl %edx			/* sector, 1-based */
	movb %dl, %bl			/* park the sector */
	xorl %edx, %edx
	movl $2, %ecx
	divl %ecx			/* %eax = cylinder, %edx = head */
	movb %dl, %bh			/* head */
	/* The cylinder is ten bits. CH takes its low eight; CL's top two
	 * take the rest, sharing the byte with the six-bit sector. */
	movb %al, %ch
	movb %al, %dl			/* scratch for the high bits */
	shrb $6, %dl
	andb $0x03, %dl
	andb $0x3F, %bl
	shlb $6, %dl
	orb %dl, %bl
	movb %bl, %cl
	movw %si, %bx			/* the destination, back where it was */
	movb boot_drive, %dl
	movb $0x01, %al			/* one sector */
	movb $0x02, %ah			/* read it */
	int $0x13
	popl %esi
	popl %ecx
	popl %edx
	popl %eax
	ret

/* The boot sector's messages. They have to be inside the 512 bytes, which
 * is why they are separate from the loader's. */
bs_msg_start:	.asciz "bunix: loading"
		.byte 13, 10, 0
bs_msg_nodisk:	.asciz "bunix: could not read the loader"
		.byte 13, 10, 0

/* Variables the boot sector writes. loader_sectors belongs here rather
 * than with the other build-patched words in the loader: the boot sector
 * has to know how many sectors to read before it can read them, and the
 * loader's copy is still zero at that moment, which would underflow and
 * read the whole disk looking for the end of a three-sector loader. */
	.align 4
boot_drive:	.byte 0
		.byte 0, 0, 0
read_lba:	.long 0
mem_lower_kb:	.long 0
mem_upper_kb:	.long 0
loader_sectors:	.long 0

/* ------------------------------------------------------------------------ */
/* The loader body: the sectors after the boot sector.                      */
/* ------------------------------------------------------------------------ */

.section .loader, "ax"
.code16
loader_body:
	/* The BIOS does not promise to leave the segment registers alone,
	 * and the calls the boot sector made have already had their way
	 * with them. Everything here addresses its own data through %ds:
	 * offsets, so %ds is put back to zero before anything is read or
	 * printed. */
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es

	movw $msg_video, %si
	call print

	/* Look for the mode the kernel wants. The mode number for
	 * 1024x768x32 is not fixed across cards, so it is looked up rather
	 * than assumed. */
	call vbe_find_mode

	/* The BIOS memory map, in the shape the kernel already parses. */
	call build_mmap

	/* Fill in the parts of the Multiboot structure that came from the
	 * BIOS but live past the point where the BIOS can be called. */
	call fill_info

	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw $msg_prot, %si
	call print
	jmp enter_protected

	/* 32-bit from here, and this is where the kernel gets loaded.
	 *
	 * It would be simpler to read the kernel with the BIOS, the way the
	 * boot sector reads this loader. That cannot work: a BIOS call
	 * writes through a real-mode segment, so it can only reach the
	 * first megabyte, and the kernel is linked at 0x100000 and is more
	 * than a megabyte besides. Reading it low and copying it up would
	 * need the copy to happen in protected mode anyway, so the read may
	 * as well be done there too.
	 *
	 * What reads it is the same ATA PIO protocol the kernel's own block
	 * driver speaks: put the sector number in the drive/head and LBA
	 * ports, ask for one sector, wait for the drive to say it has data,
	 * then take 256 words off the data port. The drive is the primary
	 * one, which is what the installer writes to and what a machine
	 * boots from.
	 *
	 * protected_entry is where the far jump in enter_protected lands.
	 * It is a jump and not a call and return on purpose: a call in a
	 * 16-bit code segment pushes a two-byte return offset, and the ret
	 * that met it on the other side would pop four, because the code
	 * segment there is 32-bit. The two bytes of difference are the
	 * low half of whatever was below the stack, which is how a
	 * bootloader ends up executing something at an address like
	 * 0x31fa4040 and triple-faulting. */
.code32
protected_entry:
	/* Interrupts off before touching the disk. The ATA command below
	 * makes the drive raise its interrupt line, and there is no IDT yet:
	 * the descriptor table register still points at the real-mode
	 * interrupt vector table, so the interrupt would be dispatched
	 * through four bytes of BIOS data as if they were a gate and the
	 * machine would triple-fault before the kernel ever started. The
	 * kernel sets up its own IDT and turns interrupts back on later;
	 * until then there is nothing here that wants them. */
	cli
	movw $0x10, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw %ax, %fs
	movw %ax, %gs
	movl $0x00090000, %esp
	movl %esp, %ebp

	movl payload_sectors, %ecx	/* sectors still to read */
	movl loader_sectors, %ebx	/* the LBA the kernel starts at */
	movl $0x00100000, %edi		/* where it is being read to */
load_kernel:
	testl %ecx, %ecx
	jz kernel_ready
	pushl %ecx
	pushl %ebx
	pushl %edi
	call ata_read_sector
	popl %edi
	popl %ebx
	popl %ecx
	testl %eax, %eax
	jz kernel_failed
	addl $512, %edi
	incl %ebx
	decl %ecx
	jmp load_kernel

kernel_failed:
	movl $msg_nodisk32, %esi
	call print32
	jmp hang

kernel_ready:
	/* Hand over. The entry point is an immediate in a far jump, so it
	 * cannot come out of a register; it is jumped to indirectly through
	 * a far pointer the build script patches instead. */
	movl $(0x2BADB002), %eax
	movl $mb_info, %ebx
	ljmp *kernel_far

/* Read the sector whose 28-bit number is in %ebx into %edi.
 *
 * Returns 1 in %eax on success and 0 on failure. The port numbers and the
 * handshaking are the ones in the ATA specification for a PIO read, and
 * match block/ata.ha, so a drive that works for the kernel works here.
 *
 * Every wait counts down rather than waiting forever. A drive that is not
 * there leaves the status port reading 0xFF, where the ready bit is never
 * set, and an endless loop would turn a missing disk into a silent hang
 * instead of a message. */
ata_read_sector:
	/* Drive and head, with the top four bits of the LBA. */
	movl %ebx, %eax
	shrl $24, %eax
	andl $0x0F, %eax
	orl $0xE0, %eax
	movw $0x1F6, %dx
	outb %al, %dx

	/* The count, then the three low bytes of the LBA. */
	movb $1, %al
	movw $0x1F2, %dx
	outb %al, %dx
	movl %ebx, %eax
	movw $0x1F3, %dx
	outb %al, %dx
	movl %ebx, %eax
	shrl $8, %eax
	movw $0x1F4, %dx
	outb %al, %dx
	movl %ebx, %eax
	shrl $16, %eax
	movw $0x1F5, %dx
	outb %al, %dx

	/* And the read command. */
	movb $0x20, %al
	movw $0x1F7, %dx
	outb %al, %dx

	/* Wait for the drive to drop busy, then to raise data-request. */
	movl $1000000, %ecx
1:
	movw $0x1F7, %dx
	inb %dx, %al
	testb $0x80, %al		/* busy */
	jz 2f
	decl %ecx
	jnz 1b
	xorl %eax, %eax
	ret
2:
	movl $1000000, %ecx
3:
	movw $0x1F7, %dx
	inb %dx, %al
	testb $0x01, %al		/* error */
	jnz 4f
	testb $0x40, %al		/* data request */
	jnz 5f
	decl %ecx
	jnz 3b
4:
	xorl %eax, %eax
	ret
5:
	/* 256 words off the data port, straight at the destination. The
	 * port is sixteen bits wide and is read as a word: one word per
	 * read is also what tells the drive that a word has been taken,
	 * and splitting each word into two byte reads would take the
	 * count apart from the data and leave the next command waiting on
	 * a transfer that never finished. */
	movw $0x1F0, %dx
	movl $256, %ecx
6:
	inw %dx, %ax
	movw %ax, (%edi)
	addl $2, %edi
	decl %ecx
	jnz 6b
	movl $1, %eax
	ret

/* Print the string at %esi, in 32-bit mode, to the serial port. The BIOS
 * text routine is not available once the CPU has left real mode, and this
 * only has a few short strings to say, so it talks to the UART rather than
 * attempting to draw anything. */
print32:
	movw $0x3F8, %dx
1:
	lodsb
	testb %al, %al
	jz 2f
	outb %al, %dx
	jmp 1b
2:
	ret


hang:
	cli
1:	hlt
	jmp 1b

/* ---- BIOS helpers ---------------------------------------------------- */

.code16

/* Print the string at %si, in real mode. */
print:
	pushw %ax
	pushw %dx
1:	lodsb
	testb %al, %al
	jz 2f
	movb %al, %ah
	movb $0xF8, %dl
	movb $0x03, %dh
	movb %ah, %al
	outb %al, %dx
	jmp 1b
2:	popw %dx
	popw %ax
	ret

/* Ask VBE for the mode that is 1024x768 with 32 bits of colour, and set
 * it. If there is no VBE, or no such mode, the kernel still boots: it
 * falls back to the text console and fb::active() stays false. */
vbe_find_mode:
	/* Controller information into 0x7000. */
	movl $0x00007000, %edi
	movl $0x4F00, %eax
	movw $0x4F00, (%edi)
	int $0x10
	cmpw $0x004F, %ax
	jne vbe_none

	/* The mode list hangs off the controller information: a far
	 * pointer at offset 14. */
	movw 0x0000700E, %si
	movw 0x00007010, %ax
	movw %ax, %fs
vbe_next:
	movw %fs:(%si), %cx
	addw $2, %si
	cmpw $0xFFFF, %cx
	je vbe_none			/* end of the list */

	/* Describe the mode into 0x7200, then look at what it says. */
	movl $0x00007200, %edi
	movl $0x4F01, %eax
	int $0x10
	cmpw $0x004F, %ax
	jne vbe_next

	cmpw $0x0400, 0x00007212	/* XResolution  == 1024 */
	jne vbe_next
	cmpw $0x0300, 0x00007214	/* YResolution  == 768 */
	jne vbe_next
	cmpb $32, 0x00007219		/* BitsPerPixel == 32 */
	jne vbe_next
	testb $0x80, 0x00007200		/* ModeAttributes: linear framebuffer */
	jz vbe_next

	/* Found one. Set it with the linear framebuffer bit turned on. */
	movw %cx, vbe_mode
	movw %cx, %bx
	orw $0x4000, %bx
	movl $0x4F02, %eax
	int $0x10
	cmpw $0x004F, %ax
	jne vbe_none

	/* The framebuffer's physical address is at offset 40 of the mode
	 * information, and the stride at 16. */
	movl 0x00007228, %eax
	movl %eax, mb_fb_addr
	movw 0x00007210, %ax
	movzwl %ax, %eax
	movl %eax, mb_fb_pitch
	movl $1, have_vbe
	ret

vbe_none:
	movl $0, have_vbe
	movw $msg_novbe, %si
	call print
	ret

/* Read the BIOS memory map into the array the kernel parses. An entry is
 * 24 bytes: a size, a 64-bit base, a 64-bit length and a type. */
build_mmap:
	pushw %es
	xorw %ax, %ax
	movw %ax, %es
	movl $mb_mmap, %edi
	xorl %ebx, %ebx
1:
	/* The Multiboot entry is the BIOS's twenty bytes with a four-byte
	 * length in front of it, so the BIOS is pointed four bytes past the
	 * start of each entry and the length is filled in afterwards. Pointing
	 * it at the start instead, as an earlier version of this did, leaves
	 * the length field holding the bottom of the base address and shifts
	 * every field in the entry along by four. */
	movl $0xE820, %eax
	movl $20, %ecx
	movl $0x534D4150, %edx		/* 'SMAP' */
	pushl %edi
	addl $4, %edi
	int $0x15
	popl %edi
	jc 2f
	cmpl $0x534D4150, %eax
	jne 2f
	movl $20, (%edi)
	addl $24, %edi
	testl %ebx, %ebx
	jnz 1b
2:
	/* The kernel wants a length in bytes, not a count of entries. */
	movl %edi, %eax
	subl $mb_mmap, %eax
	movl %eax, mb_mmap_len
	popw %es
	ret

/* Copy the values the BIOS gave into the Multiboot structure, and set the
 * flags that tell the kernel which of them are real. Bits 0 (memory), 6 (the
 * map) and 9 (the boot device) are always set; bit 12 (framebuffer) only if a
 * mode was found, which is the difference between a graphical boot and a text
 * one. */
fill_info:
	movzwl mem_lower_kb, %eax
	movl %eax, mb_mem_lower
	movl mem_upper_kb, %eax
	movl %eax, mb_mem_upper
	/* The drive the BIOS booted from, in the top byte of the word, which
	 * is where Multiboot puts it and where the kernel looks for it. It
	 * is the BIOS's own number: 0x80 is the first hard disk. */
	movzbl boot_drive, %eax
	shll $24, %eax
	movl %eax, mb_boot_device
	movl $(1 | (1 << 6) | (1 << 9)), %eax
	cmpl $0, have_vbe
	je 1f
	orl $(1 << 12), %eax
1:
	movl %eax, mb_flags
	ret

/* Load the GDT and set the protected-mode bit. The far jump after that is
 * what actually enters 32-bit mode, because the segment registers have to
 * be reloaded under the new descriptor table before the next instruction
 * can be decoded as 32-bit. */
enter_protected:
	lgdt gdt_ptr
	movl %cr0, %eax
	orl $1, %eax
	movl %eax, %cr0
	ljmp $0x08, $protected_entry

/* ---- Data ------------------------------------------------------------ */

.code16
msg_video:	.asciz "bunix: looking for a framebuffer"
		.byte 13, 10, 0
msg_prot:	.asciz "bunix: entering protected mode"
		.byte 13, 10, 0
msg_novbe:	.asciz "bunix: no 1024x768x32 mode, using the text console"
		.byte 13, 10, 0

/* The one loader message that is printed after the CPU has left real mode,
 * so it goes to the serial port and wants a plain newline rather than the
 * carriage return the BIOS text routine needs. */
msg_nodisk32:	.asciz "bunix: could not read the kernel from disk\n"

	.align 8
gdt:
	.quad 0				/* null */
	.quad 0x00CF9A000000FFFF	/* code, flat, 32-bit, ring 0 */
	.quad 0x00CF92000000FFFF	/* data, flat, 32-bit, ring 0 */
gdt_end:
gdt_ptr:
	.word gdt_end - gdt - 1
	.long gdt

vbe_mode:	.word 0
have_vbe:	.long 0

/* The Multiboot 1 information structure. The kernel checks mb_flags before
 * believing any of the fields, so only the bits for memory, the map and
 * the framebuffer need setting. */
	.align 4
mb_info:
mb_flags:	.long 0
mb_mem_lower:	.long 0
mb_mem_upper:	.long 0
mb_boot_device:	.long 0			/* filled in before the jump */
		.long 0			/* cmdline */
		.long 0			/* mods_count */
		.long 0			/* mods_addr */
		.long 0, 0, 0, 0	/* syms: four words */
mb_mmap_len:	.long 0
mb_mmap_addr:	.long mb_mmap
		.long 0			/* drives_length */
		.long 0			/* drives_addr */
		.long 0			/* config_table */
		.long 0			/* boot_loader_name */
		.long 0			/* apm_table */
		.long 0			/* vbe_control_info */
		.long 0			/* vbe_mode_info */
		.word 0			/* vbe_mode */
		.word 0			/* vbe_interface_seg */
		.word 0			/* vbe_interface_off */
		.word 0			/* vbe_interface_len */
mb_fb_addr:	.quad 0
mb_fb_pitch:	.long 0
mb_fb_width:	.long 1024
mb_fb_height:	.long 768
mb_fb_bpp:	.byte 32
mb_fb_type:	.byte 1
		.byte 0, 0

/* The memory map, filled by the BIOS call above: 24 bytes an entry, with
 * room for more than a BIOS ever returns, since the alternative is walking
 * off the end of it. */
	.align 8
mb_mmap:
	.skip 24 * 64

/* The numbers the build script patches in, plus the far pointer the final
 * jump goes through. A far jump's target is an immediate, so it has to be
 * reached indirectly for the address to be known only at build time. The
 * operand is an m16:32 far pointer, and that type puts the four-byte offset
 * first and the two-byte selector after it; the other order reads the
 * selector out of the top of the offset, which is a selector of zero and a
 * general protection fault rather than a kernel. The offset is what gets
 * patched; the selector is 0x08, the kernel's code segment in the GDT above.
 *
 * loader_sectors is not here: the boot sector needs it before this section
 * is in memory, so it lives in the boot sector with the other variables. */
	.align 4
payload_sectors:	.long 0
	.align 4
kernel_far:
	.long 0			/* patched with the kernel's entry point */
	.word 0x08

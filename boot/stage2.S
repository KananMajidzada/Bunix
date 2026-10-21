# The second stage of the boot.
#
# The boot sector reads this to 0x8000 and jumps to it. Here the memory the
# machine has is found, the kernel is read from the disk, and the kernel is
# started the way a Multiboot loader would: the number 0x2BADB002 in one
# register and the address of the information in another.
#
# The kernel is read with the drive's own ports rather than with a BIOS
# call, because a BIOS call cannot reach past the first megabyte and the
# kernel lives above it.

.code16
.text
.global _start
_start:
	cld
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw $0x5000, %sp

	# Where the kernel is, and how much of it there is. The boot sector
	# left the record in memory, and the second stage reads it from there.
	movl $0x7D80, %eax	# 0x7C00 + 0x180
	movl 0x08(%eax), %ebx	# the first sector of the kernel
	movl %ebx, lbanow
	movl 0x0C(%eax), %ebx	# how many sectors
	movl %ebx, sectors
	movl $0x100000, %eax
	movl %eax, dest

	# The kernel, a piece at a time.
loop:
	movl sectors, %eax
	cmpl $0, %eax
	je loaded
	# One sector at a time, which every drive does.
	movl $1, %ecx
1:	call read_sectors
	jc diskerr
	# On to the next piece.
	movl count, %ecx
	shll $9, %ecx		# a piece is this many bytes
	movl dest, %eax
	addl %ecx, %eax
	movl %eax, dest
	movl lbanow, %eax
	movl count, %ecx
	addl %ecx, %eax
	movl %eax, lbanow
	movl sectors, %eax
	subl count, %eax
	movl %eax, sectors
	jmp loop

loaded:
	movw $readmsg, %si
	call puts

	# The information the kernel reads: how much memory there is, and
	# the map of it. The boot sector asked the BIOS, and left the
	# answers in the record.
	movl $0x41, 0x7000		# the flags: memory, and a map
	movw $0x400, %ax
	movl %eax, 0x7004		# the memory below the first megabyte
	movl 0x7D98, %eax
	movl %eax, 0x7008		# the memory above it
	movl 0x7D9C, %eax
	movl %eax, 0x702C		# how long the map is
	movl $0x7100, %eax
	movl %eax, 0x7030		# where the map is

	movw $jumpmsg, %si
	call puts

	# The kernel is written in thirty-two-bit code, so the machine has
	# to be in protected mode before it is started. The table of segments
	# is loaded, the bit that turns on protection is set, and a far jump
	# with a thirty-two-bit offset finishes the change of mode.
	lgdt gdtdesc
	movl %cr0, %eax
	orl $1, %eax
	movl %eax, %cr0
	.byte 0x66, 0xEA		# a far jump with a thirty-two-bit offset
	.long protected
	.word 0x0008

# Reads the sectors into the memory at dest. The number of them is in %ecx
# and the first one is in lbanow. The carry flag is set if the drive says no.
read_sectors:
	pushw %ax
	pushw %cx
	pushw %dx
	movl %ecx, count
	# Wait for the drive to be ready: keep going while it is busy.
1:	movw $0x1F7, %dx
	inb %dx, %al
	testb $0x80, %al		# is it busy
	jnz 1b
	testb $0x01, %al		# did it go wrong
	jnz diskerr
	# The drive, and the top of the number of the sector.
	movw $0x1F6, %dx
	movb $0xE0, %al		# the first drive, counting in blocks
	outb %al, %dx
	# The number of the sector. The three parts of it have their own
	# places: the first is at 0x1F3, the next at 0x1F4 and the last at
	# 0x1F5. The count of sectors has a place of its own at 0x1F2.
	movw $0x1F3, %dx
	movb lbanow, %al
	outb %al, %dx
	movw $0x1F4, %dx
	movb lbanow+1, %al
	outb %al, %dx
	movw $0x1F5, %dx
	movb lbanow+2, %al
	outb %al, %dx
	# How many sectors to read.
	movw $0x1F2, %dx
	movb %cl, %al
	outb %al, %dx
	# The command: read them.
	movw $0x1F7, %dx
	movb $0x20, %al
	outb %al, %dx
	# Wait for the data to be there.
2:	movw $0x1F7, %dx
	inb %dx, %al
	testb $0x80, %al		# is it busy
	jnz 2b
	testb $0x08, %al		# is the data ready
	jnz gotdata
	# Something went wrong: say what the drive says.
	movb %al, %ah
	call puthex
	jc diskerr
gotdata:
	# The data itself. The address override lets it reach above the
	# first megabyte, which is where the kernel goes.
	movl dest, %edi
	movw $0x1F0, %dx
	movl count, %ecx
	shll $8, %ecx		# the words in the sectors
	.byte 0xf3, 0x67, 0x6d	# rep insw
	popw %dx
	popw %cx
	popw %ax
	clc
	ret

diskerr:
	movw $errmsg, %si
	call puts
diskstop:
	hlt
	jmp diskstop

# Prints the string at %si, which ends in a zero, on the serial line.
puts:
	pushw %ax
	pushw %dx
1:	lodsb
	testb %al, %al
	je 2f
	movb %al, %ah
3:	movw $0x3FD, %dx
	inb %dx, %al
	testb $0x20, %al
	jz 3b
	movb %ah, %al
	movw $0x3F8, %dx
	outb %al, %dx
	jmp 1b
2:	popw %dx
	popw %ax
	ret

# Shows the number in %eax on the serial line, in hex.
puthex:
	pushw %ax
	pushw %bx
	pushw %cx
	pushw %dx
	movl %eax, %ebx
	movl $8, %ecx
1:	shrl $4, %ebx
	movb %bl, %al
	andb $0x0F, %al
	call hexone
	call serial
	loop 1b
	popw %dx
	popw %cx
	popw %bx
	popw %ax
	ret

# The low four bits of %al as a character.
hexone:
	andb $0x0F, %al
	cmpb $9, %al
	jbe 1f
	addb $0x37, %al
	ret
1:	addb $0x30, %al
	ret

# Sends the byte in %al out of the serial line.
serial:
	pushw %ax
	pushw %dx
	movb %al, %ah
	movw $0x3FD, %dx
1:	inb %dx, %al
	testb $0x20, %al
	jz 1b
	movb %ah, %al
	movw $0x3F8, %dx
	outb %al, %dx
	popw %dx
	popw %ax
	ret

errmsg:
	.asciz "Bunix: cannot read the disk\r\n"
readmsg:
	.asciz "Bunix: kernel read\r\n"
jumpmsg:
	.asciz "Bunix: jumping\r\n"

# The last part of the boot is in protected mode, so that the kernel can be
# started where it is linked. It comes last, so that the code before it is
# assembled as sixteen-bit code.
.code32
protected:
	movw $0x10, %ax
	movw %ax, %ds
	movw %ax, %es
	movw $0x10, %ax
	movw %ax, %ss
	movw $0x5000, %sp
protected2:
	# The kernel is where it was linked, and the information about the
	# machine is at 0x7000. The number the kernel looks for goes in one
	# register and the address to jump to in another.
	movl $0x7D80, %eax
	movzwl 0x14(%eax), %ecx	# where in the kernel to start
	movl $0x100000, %edx
	addl %ecx, %edx
	movl $0x7000, %ebx
	movl $0x2BADB002, %eax
	jmp *%edx

.section .data
	.align 8
# A table for protected mode: nothing, a piece of code, and a piece of data.
gdt:
	.quad 0x0000000000000000
	.quad 0x00CF9A000000FFFF
	.quad 0x00CF92000000FFFF
gdtdesc:
	.word gdtdesc - gdt - 1
	.long gdt

lbanow:	.long 0
sectors:	.long 0
count:		.long 0
dest:		.long 0
memlower:	.word 0
memupper:	.long 0

# The boot sector that puts Bunix on a disk.
#
# The BIOS loads this at 0x7C00 in 16-bit real mode and jumps to it. Its job
# is small: ask the BIOS for the map of memory, read the second stage from
# the disk, and jump to it. The second stage is the one that loads the
# kernel, because a BIOS call cannot reach past the first megabyte and the
# kernel lives above it.
#
# The map is asked for first, because the BIOS will not give it again once
# the disk has been read.

.code16
.text
.global _start
_start:
	cli
	cld
	xorw %ax, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	movw $0x7C00, %sp
	movb %dl, bootdrive

	# The map of memory, from the BIOS, in the shape the kernel reads: the
	# size, the base, the length and the kind, twenty-four bytes to a
	# place. The BIOS gives it in another order, so it is put where the
	# kernel looks.
	movw $0x7100, mapdest
	movl $0, maplen
	movl $0, highest
	movl $0, %ebx
maploop:
	movl $0xE820, %eax
	movl $0x534D4150, %edx
	movl $24, %ecx
	movw $0x6000, %di
	int $0x15
	jc mapdone
	# The last place is marked with a zero, and the map ends there.
	cmpl $0, %ebx
	jz mapdone
	# The map has room for so many places, and no more.
	movw mapdest, %ax
	cmpw $0x7700, %ax
	jae mapdone
	# The size, the base, the length and the kind.
	movw mapdest, %di
	movl $20, (%di)
	movl 0x6000, %eax
	movl %eax, 4(%di)
	movl 0x6004, %eax
	movl %eax, 8(%di)
	movl 0x6008, %eax
	movl %eax, 12(%di)
	movl 0x600C, %eax
	movl %eax, 16(%di)
	movl 0x6010, %eax
	movl %eax, 20(%di)
	# Keep the highest place the memory reaches.
	movl 0x6000, %eax
	movl 0x6008, %ecx
	addl %ecx, %eax
	cmpl highest, %eax
	jbe 1f
	movl %eax, highest
1:	addw $24, %di
	movw %di, mapdest
	addl $24, maplen
	jmp maploop
mapdone:
	# How much memory there is above the first megabyte, and how long the
	# map is. Both go in the record, for the second stage.
	movl highest, %eax
	subl $0x100000, %eax
	shrl $10, %eax
	movl %eax, 0x7D98
	movl maplen, %eax
	movl %eax, 0x7D9C

	# Say something, so that a machine that cannot read the disk says so.
	movw $message, %si
	call puts

	# The second stage: the four sectors after this one, to 0x8000. It is
	# read the old way, with the cylinder, the head and the sector named,
	# because that is the one every BIOS understands.
	movw $0x0800, %ax
	movw %ax, %es
	xorw %bx, %bx
	movb $0x02, %ah		# read sectors
	movb $4, %al		# how many sectors
	movw $0x0002, %cx	# the cylinder and the sector
	xorw %dx, %dx		# the head
	movb bootdrive, %dl	# the drive
	int $0x13
	jc diskerr

	# On to the second stage.
	ljmp $0x0000, $0x8000

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

diskerr:
	movw $errmsg, %si
	call puts
diskstop:
	hlt
	jmp diskstop

message:
	.asciz "Bunix boot\r\n"
errmsg:
	.asciz "Bunix: no disk\r\n"

.section .data
	# The record the installer fills in. It is at a fixed place in the
	# sector, so that the installer can find it without knowing anything
	# about the code, and so that the second stage can read it from the
	# copy of this sector that is in memory.
	.org 0x00
	.ascii "BUNIX"
	.org 0x08
kernellba:	.long 0
	.org 0x0C
kernelsectors:	.long 0
	.org 0x10
datalba:	.long 0
	.org 0x14
entryoff:	.long 0x1000
	.org 0x18
	.long 0			# the memory above the first megabyte
	.org 0x1C
	.long 0			# the length of the map
	.org 0x20
bootdrive:	.byte 0
mapdest:	.word 0
maplen:		.long 0
highest:	.long 0

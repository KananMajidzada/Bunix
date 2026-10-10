.text

.global arch.outb
arch.outb:
	movw %di, %dx
	movb %sil, %al
	outb %al, %dx
	ret

.global arch.inb
arch.inb:
	movw %di, %dx
	xorl %eax, %eax
	inb %dx, %al
	ret

.global arch.outw
arch.outw:
	movw %di, %dx
	movw %si, %ax
	outw %ax, %dx
	ret

.global arch.inw
arch.inw:
	movw %di, %dx
	xorl %eax, %eax
	inw %dx, %ax
	ret

.global arch.cli
arch.cli:
	cli
	ret

.global arch.sti
arch.sti:
	sti
	ret

/* A short delay by writing to the unused port 0x80. */
.global arch.io_wait
arch.io_wait:
	xorl %eax, %eax
	movw $0x80, %dx
	outb %al, %dx
	ret

/* Read one byte, used to provoke a fault on an unmapped address. */
.global arch.probe
arch.probe:
	movq %rdi, %rax
	movb (%rax), %al
	ret

.global arch.pause
arch.pause:
	pause
	ret

.global arch.ltr
arch.ltr:
	movw %di, %ax
	ltr %ax
	ret

.global arch.read_cr3
arch.read_cr3:
	movq %cr3, %rax
	ret

.global arch.write_cr3
arch.write_cr3:
	movq %rdi, %cr3
	ret

.global arch.invlpg
arch.invlpg:
	invlpg (%rdi)
	ret

.text

.global architecture.outb
architecture.outb:
	movw %di, %dx
	movb %sil, %al
	outb %al, %dx
	ret

.global architecture.inb
architecture.inb:
	movw %di, %dx
	xorl %eax, %eax
	inb %dx, %al
	ret

.global architecture.outw
architecture.outw:
	movw %di, %dx
	movw %si, %ax
	outw %ax, %dx
	ret

.global architecture.inw
architecture.inw:
	movw %di, %dx
	xorl %eax, %eax
	inw %dx, %ax
	ret

.global architecture.outl
architecture.outl:
	movw %di, %dx
	movl %esi, %eax
	outl %eax, %dx
	ret

.global architecture.inl
architecture.inl:
	movw %di, %dx
	xorl %eax, %eax
	inl %dx, %eax
	ret

.global architecture.insl
architecture.insl:
	movl %edx, %ecx
	movw %di, %dx
	movq %rsi, %rdi
	cld
	rep insl (%dx), %es:(%rdi)
	ret

.global architecture.outsl
architecture.outsl:
	movl %edx, %ecx
	movw %di, %dx
	movq %rsi, %rdi
	cld
	rep outsl %ds:(%rsi), (%dx)
	ret

.global architecture.cli
architecture.cli:
	cli
	ret

.global architecture.sti
architecture.sti:
	sti
	ret

/* A short delay by writing to the unused port 0x80. */
.global architecture.io_wait
architecture.io_wait:
	xorl %eax, %eax
	movw $0x80, %dx
	outb %al, %dx
	ret

/* Read one byte, used to provoke a fault on an unmapped address. */
.global architecture.probe
architecture.probe:
	movq %rdi, %rax
	movb (%rax), %al
	ret

.global architecture.pause
architecture.pause:
	pause
	ret

/* Return RFLAGS and disable interrupts; pair with irq_restore. */
.global architecture.irq_save
architecture.irq_save:
	pushfq
	popq %rax
	cli
	ret

.global architecture.irq_restore
architecture.irq_restore:
	pushq %rdi
	popfq
	ret

/* Block copy through rep movsq, finishing the tail with bytes. */
.global architecture.memcpy
architecture.memcpy:
	movq %rdx, %rcx
	shrq $3, %rcx
	cld
	rep movsq
	movq %rdx, %rcx
	andq $7, %rcx
	rep movsb
	ret

/* Fill through rep stosq with a repeating 8-byte word. */
.global architecture.store64
architecture.store64:
	movq %rsi, %rax
	movq %rdx, %rcx
	cld
	rep stosq
	ret

.global architecture.ltr
architecture.ltr:
	movw %di, %ax
	ltr %ax
	ret

.global architecture.read_cr3
architecture.read_cr3:
	movq %cr3, %rax
	ret

.global architecture.write_cr3
architecture.write_cr3:
	movq %rdi, %cr3
	ret

.global architecture.read_cr0
architecture.read_cr0:
	movq %cr0, %rax
	ret

.global architecture.write_cr0
architecture.write_cr0:
	movq %rdi, %cr0
	ret

.global architecture.read_cr4
architecture.read_cr4:
	movq %cr4, %rax
	ret

.global architecture.write_cr4
architecture.write_cr4:
	movq %rdi, %cr4
	ret

# Puts the FPU and SSE into a known state. fxrstor leaves the registers at
# whatever the last fxsave recorded, so the image is set up first and the
# control words are cleared, which also sets the x87 tag word.
.global architecture.fpu_init
architecture.fpu_init:
	fninit
	fxsave (%rdi)
	fxrstor (%rdi)
	ret

.global architecture.fpu_save
architecture.fpu_save:
	fxsave (%rdi)
	ret

.global architecture.fpu_load
architecture.fpu_load:
	fxrstor (%rdi)
	ret

.global architecture.invlpg
architecture.invlpg:
	invlpg (%rdi)
	ret

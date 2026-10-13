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

.global arch.outl
arch.outl:
	movw %di, %dx
	movl %esi, %eax
	outl %eax, %dx
	ret

.global arch.inl
arch.inl:
	movw %di, %dx
	xorl %eax, %eax
	inl %dx, %eax
	ret

.global arch.insl
arch.insl:
	movl %edx, %ecx
	movw %di, %dx
	movq %rsi, %rdi
	cld
	rep insl (%dx), %es:(%rdi)
	ret

.global arch.outsl
arch.outsl:
	movl %edx, %ecx
	movw %di, %dx
	movq %rsi, %rdi
	cld
	rep outsl %ds:(%rsi), (%dx)
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

/* Return RFLAGS and disable interrupts; pair with irq_restore. */
.global arch.irq_save
arch.irq_save:
	pushfq
	popq %rax
	cli
	ret

.global arch.irq_restore
arch.irq_restore:
	pushq %rdi
	popfq
	ret

/* Block copy through rep movsq, finishing the tail with bytes. */
.global arch.memcpy
arch.memcpy:
	movq %rdx, %rcx
	shrq $3, %rcx
	cld
	rep movsq
	movq %rdx, %rcx
	andq $7, %rcx
	rep movsb
	ret

/* Fill through rep stosq with a repeating 8-byte word. */
.global arch.store64
arch.store64:
	movq %rsi, %rax
	movq %rdx, %rcx
	cld
	rep stosq
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

.global arch.read_cr0
arch.read_cr0:
	movq %cr0, %rax
	ret

.global arch.write_cr0
arch.write_cr0:
	movq %rdi, %cr0
	ret

.global arch.read_cr4
arch.read_cr4:
	movq %cr4, %rax
	ret

.global arch.write_cr4
arch.write_cr4:
	movq %rdi, %cr4
	ret

# Puts the FPU and SSE into a known state. fxrstor leaves the registers at
# whatever the last fxsave recorded, so the image is set up first and the
# control words are cleared, which also sets the x87 tag word.
.global arch.fpu_init
arch.fpu_init:
	fninit
	fxsave (%rdi)
	fxrstor (%rdi)
	ret

.global arch.fpu_save
arch.fpu_save:
	fxsave (%rdi)
	ret

.global arch.fpu_load
arch.fpu_load:
	fxrstor (%rdi)
	ret

.global arch.invlpg
arch.invlpg:
	invlpg (%rdi)
	ret

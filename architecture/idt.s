.text

.section .data
.global architecture.cr2_addr
architecture.cr2_addr:
	.quad 0

.text

.macro isr_noerr n
isr_\n:
	pushq $0
	pushq $\n
	jmp isr_common
.endm

.macro isr_err n
isr_\n:
	pushq $\n
	jmp isr_common
.endm

isr_noerr 0
isr_noerr 1
isr_noerr 2
isr_noerr 3
isr_noerr 4
isr_noerr 5
isr_noerr 6
isr_noerr 7
isr_err   8
isr_noerr 9
isr_err   10
isr_err   11
isr_err   12
isr_err   13

# Page fault: keep the faulting address before the frame is built.
isr_14:
	movq %cr2, %rax
	movq %rax, architecture.cr2_addr(%rip)
	pushq $14
	jmp isr_common

isr_noerr 15
isr_noerr 16
isr_err   17
isr_noerr 18
isr_noerr 19
isr_noerr 20
isr_err   21
isr_noerr 22
isr_noerr 23
isr_noerr 24
isr_noerr 25
isr_noerr 26
isr_noerr 27
isr_noerr 28
isr_err   29
isr_err   30
isr_noerr 31

isr_noerr 32
isr_noerr 33
isr_noerr 34
isr_noerr 35
isr_noerr 36
isr_noerr 37
isr_noerr 38
isr_noerr 39
isr_noerr 40
isr_noerr 41
isr_noerr 42
isr_noerr 43
isr_noerr 44
isr_noerr 45
isr_noerr 46
isr_noerr 47

isr_noerr 128

isr_default:
	pushq $0
	pushq $0xFF
	jmp isr_common

isr_common:
	pushq %rax
	pushq %rbx
	pushq %rcx
	pushq %rdx
	pushq %rsi
	pushq %rdi
	pushq %rbp
	pushq %r8
	pushq %r9
	pushq %r10
	pushq %r11
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	cld
	movq %rsp, %rdi
	andq $-16, %rsp
	call architecture.isr_handler
	movq %rax, %rsp
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %r11
	popq %r10
	popq %r9
	popq %r8
	popq %rbp
	popq %rdi
	popq %rsi
	popq %rdx
	popq %rcx
	popq %rbx
	popq %rax
	addq $16, %rsp
	iretq

.global architecture.load_idt
architecture.load_idt:
	lidt (%rdi)
	ret

.section .rodata
.align 8
.global architecture.isr_stubs
architecture.isr_stubs:
	.quad isr_0
	.quad isr_1
	.quad isr_2
	.quad isr_3
	.quad isr_4
	.quad isr_5
	.quad isr_6
	.quad isr_7
	.quad isr_8
	.quad isr_9
	.quad isr_10
	.quad isr_11
	.quad isr_12
	.quad isr_13
	.quad isr_14
	.quad isr_15
	.quad isr_16
	.quad isr_17
	.quad isr_18
	.quad isr_19
	.quad isr_20
	.quad isr_21
	.quad isr_22
	.quad isr_23
	.quad isr_24
	.quad isr_25
	.quad isr_26
	.quad isr_27
	.quad isr_28
	.quad isr_29
	.quad isr_30
	.quad isr_31
	.quad isr_32
	.quad isr_33
	.quad isr_34
	.quad isr_35
	.quad isr_36
	.quad isr_37
	.quad isr_38
	.quad isr_39
	.quad isr_40
	.quad isr_41
	.quad isr_42
	.quad isr_43
	.quad isr_44
	.quad isr_45
	.quad isr_46
	.quad isr_47
	.rept 80
	.quad isr_default
	.endr
	.quad isr_128
	.rept 127
	.quad isr_default
	.endr

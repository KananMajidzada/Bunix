.section .text
.globl _start
_start:
	movq $2, %rax
	leaq path(%rip), %rdi
	movq $pathlen, %rsi
	leaq buf(%rip), %rdx
	movq $256, %rcx
	int $0x80

	movq %rax, %rsi
	movq $1, %rax
	leaq buf(%rip), %rdi
	int $0x80

	movq $0, %rax
	int $0x80
1:	jmp 1b

path:
	.ascii "/proc/version"
	.set pathlen, . - path

.section .data
buf:
	.space 256

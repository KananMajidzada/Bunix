.section .text
.globl _start
_start:
	movq $1, %rax
	leaq message(%rip), %rdi
	movq $msglen, %rsi
	int $0x80
	movq $0, %rax
	int $0x80
1:	jmp 1b

message:
	.ascii "hello from user mode\n"
	.set msglen, . - message

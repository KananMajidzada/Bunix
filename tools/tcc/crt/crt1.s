/* crt1.s - C runtime startup.
 *
 * The loader jumps here with:
 *   %rdi = pointer to argument buffer
 *   %rsi = length of argument buffer
 *
 * We set up the C runtime and call __libc_start, which parses the
 * argument string into argc/argv and calls main.
 */
.section .text
.global _start
.type _start, @function
_start:
	/* No frame above us; no return address to skip. */
	xorq %rbp, %rbp
	andq $-16, %rsp
	call __libc_start
1:	jmp 1b
.size _start, .-_start
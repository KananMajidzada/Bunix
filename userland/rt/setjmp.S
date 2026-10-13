/* setjmp and longjmp for x86-64.
 *
 * The buffer holds the six callee-saved registers, then the stack pointer to
 * come back to and the address to resume at:
 *
 *     0  rbx        32 r14        48 rsp to restore
 *     8  rbp        40 r15        56 address to resume at
 *     16 r12
 *     24 r13
 *
 * setjmp records where its own return address is and where the stack will be
 * once it has returned, so longjmp restores both and jumps. The jump lands
 * exactly where the call to setjmp returned, so from the caller's point of
 * view the function resumed.
 *
 * Neither touches the stack below %rsp, so no frame is needed and there is
 * nothing to unwind. */

.section .text

.global setjmp
.type setjmp, @function
setjmp:
	movq  %rbx, 0(%rdi)
	movq  %rbp, 8(%rdi)
	movq  %r12, 16(%rdi)
	movq  %r13, 24(%rdi)
	movq  %r14, 32(%rdi)
	movq  %r15, 40(%rdi)
	leaq  8(%rsp), %rax		/* where %rsp will be after the ret */
	movq  %rax, 48(%rdi)
	movq  (%rsp), %rax		/* the caller's return address */
	movq  %rax, 56(%rdi)
	xorl  %eax, %eax			/* setjmp always reports 0 */
	ret
.size setjmp, .-setjmp

.global _setjmp
.type _setjmp, @function
_setjmp:
	jmp   setjmp
.size _setjmp, .-_setjmp

.global longjmp
.type longjmp, @function
longjmp:
	movl  %esi, %eax
	testl %eax, %eax
	jne   1f
	movl  $1, %eax			/* longjmp(env, 0) acts as 1 */
1:
	movq  0(%rdi), %rbx
	movq  8(%rdi), %rbp
	movq  16(%rdi), %r12
	movq  24(%rdi), %r13
	movq  32(%rdi), %r14
	movq  40(%rdi), %r15
	movq  48(%rdi), %rsp
	jmp   *56(%rdi)
.size longjmp, .-longjmp

.global _longjmp
.type _longjmp, @function
_longjmp:
	jmp   longjmp
.size _longjmp, .-_longjmp
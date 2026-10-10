.text

.global rt.sys_exit
rt.sys_exit:
	movq $0, %rax
	int $0x80
1:	jmp 1b

.global rt.sys_write
rt.sys_write:
	movq $1, %rax
	int $0x80
	ret

.global rt.sys_read
rt.sys_read:
	movq $2, %rax
	int $0x80
	ret

.global rt.sys_alloc
rt.sys_alloc:
	movq $3, %rax
	int $0x80
	ret

.data
.align 8
.global rt.arg_ptr
rt.arg_ptr:
	.quad 0
.global rt.arg_len
rt.arg_len:
	.quad 0

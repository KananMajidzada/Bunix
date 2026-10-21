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

.global rt.sys_writefile
rt.sys_writefile:
	movq $4, %rax
	int $0x80
	ret

.global rt.sys_appendfile
rt.sys_appendfile:
	movq $15, %rax
	int $0x80
	ret

.global rt.sys_readchr
rt.sys_readchr:
	movq $5, %rax
	int $0x80
	ret

.global rt.sys_yield
rt.sys_yield:
	movq $6, %rax
	int $0x80
	ret

.global rt.sys_create
rt.sys_create:
	movq $7, %rax
	int $0x80
	ret

.global rt.sys_remove
rt.sys_remove:
	movq $8, %rax
	int $0x80
	ret

.global rt.sys_readdir
rt.sys_readdir:
	movq $9, %rax
	int $0x80
	ret

.global rt.sys_halt
rt.sys_halt:
	movq $10, %rax
	int $0x80
1:	jmp 1b

.global rt.sys_spawn
rt.sys_spawn:
	movq $11, %rax
	int $0x80
	ret

.global rt.sys_spawn_shared
rt.sys_spawn_shared:
	movq $14, %rax
	int $0x80
	ret

.global rt.sys_alive
rt.sys_alive:
	movq $12, %rax
	int $0x80
	ret

.global rt.sys_fresh
rt.sys_fresh:
	movq $13, %rax
	int $0x80
	ret

.global rt.sys_stat
rt.sys_stat:
	movq $16, %rax
	int $0x80
	ret

.global rt.sys_screen
rt.sys_screen:
	movq $17, %rax
	int $0x80
	ret

.global rt.sys_chdir
rt.sys_chdir:
	movq $18, %rax
	int $0x80
	ret

.global rt.sys_pwd
rt.sys_pwd:
	movq $19, %rax
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

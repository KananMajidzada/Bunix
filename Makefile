.POSIX:
.SUFFIXES:
.SECONDARY:

include config.mk

SRCS = $(shell find . -name '*.ha' -o -name '*.s' -o -name '*.sc')

# Programs that get an image of their own. The shell runs them by name.
# Each one ends up as both a real ELF (for nm, to read _start and __image_end)
# and a flat blob (the bytes the loader copies into user memory).
PROGS = hello wc grep cp cc test_c fbtest tcc mei \
	ls sort uniq head tail tr rev seq expr basename dirname \
	stat du df test find tree \
	mv nl cut paste comm diff od strings cksum file uname id split \
	ps kill install

# Programs written in Hare, built by the Hare compiler.
HARE_PROGS = $(filter-out $(C_PROGS),$(PROGS))
# Programs written in C, cross-compiled on the host by bcc.
C_PROGS = test_c fbtest

PROG_ELFS = $(addprefix build/elf_,$(PROGS))
PROG_BINS = $(addprefix build/prog_,$(addsuffix .bin,$(PROGS)))

all: bunix.bin

# The kernel is a freestanding Hare program. HAREPATH is pointed at the tree
# itself so the build only sees our runtime and modules.
bunix: user/blob.ha user/progs.ha user/progs.s user/hdrs.ha user/src.ha \
       user/crt.ha user/libc.ha user/bootsec.ha $(SRCS)
	HAREPATH=. $(HARE) build -F -a$(ARCH) -o $@

# QEMU's built-in Multiboot loader only accepts 32-bit ELF, so hand it a flat
# image and let rt/start.s raise the CPU into long mode itself.
bunix.bin: bunix
	$(OBJCOPY) -O binary bunix $@

# The user program is a freestanding Hare program with its own runtime under
# userland/. It links at a fixed address, so it becomes a flat blob folded into
# the kernel as a byte array the shell loads into the reserved user region.
USER_SRCS = $(shell find userland -name '*.ha' -o -name '*.s' -o -name '*.sc')

build/userprog: $(USER_SRCS)
	@mkdir -p build
	cd userland && HAREPATH=. $(HARE) build -F -a$(ARCH) -o $(CURDIR)/build/userprog

build/prog.bin: build/userprog
	$(OBJCOPY) -O binary $< $@

user/blob.ha: build/prog.bin
	@{ n=$$(wc -c < build/prog.bin); \
	   e=$$(nm build/userprog | awk '$$3 == "_start" { print $$1 }'); \
	   x=$$(nm build/userprog | awk '$$3 == "__image_end" { print $$1 }'); \
	   printf 'export const prog: [%s]u8 = [' "$$n"; \
	   od -An -tu1 -v build/prog.bin | awk '{ for (i = 1; i <= NF; i++) printf "%s,", $$i }'; \
	   printf '];\nexport const entry: u64 = 0x%s;\nexport const image_end: u64 = 0x%s;\n' "$$e" "$$x"; } > $@

# /usr/include holds the compiler's own headers and the C library's headers
# together, so a program written inside Bunix can say #include <stdio.h> or
# <sys/stat.h> and have it resolve. The two sets overlap (stdarg.h, stddef.h,
# float.h, stdbool.h): the compiler's copies win, because they match what the
# compiler itself understands. userland/include adds headers that exist only
# for the target.
HDRS_STAGE = build/headers
user/hdrs.ha: $(wildcard $(TCC_DIR)/include/*.h) $(wildcard userland/rt/*.h) \
              $(wildcard userland/rt/sys/*.h) $(wildcard userland/include/*.h) \
              tools/embed.py
	@rm -rf $(HDRS_STAGE)
	@mkdir -p $(HDRS_STAGE)/sys
	@cp userland/rt/*.h $(HDRS_STAGE)/
	@cp userland/rt/sys/*.h $(HDRS_STAGE)/sys/
	@cp userland/include/*.h $(HDRS_STAGE)/
	@cp $(TCC_DIR)/include/*.h $(HDRS_STAGE)/
	python3 tools/embed.py $(HDRS_STAGE) $@ header

user/src.ha: $(wildcard $(TCC_DIR)/examples/*.c) tools/embed.py
	python3 tools/embed.py $(TCC_DIR)/examples $@ src

# The boot sector that puts Bunix on a disk, and the second stage that goes
# with it. They are folded into the kernel, so that the machine can install
# itself.
build/bootsec.elf: boot/bootsec.S boot/bootsec.ld
	@mkdir -p build
	$(AS) --32 -o build/bootsec.o boot/bootsec.S
	$(LD) -m elf_i386 -T boot/bootsec.ld -o $@ build/bootsec.o

build/bootsec.bin: build/bootsec.elf
	$(OBJCOPY) -O binary $< $@

build/stage2.elf: boot/stage2.S boot/stage2.ld
	@mkdir -p build
	$(AS) --32 -o build/stage2.o boot/stage2.S
	$(LD) -m elf_i386 -T boot/stage2.ld -o $@ build/stage2.o

build/stage2.bin: build/stage2.elf
	$(OBJCOPY) -O binary $< $@

user/bootsec.ha: build/bootsec.bin build/stage2.bin
	@{ printf 'export const bootsec: [%s]u8 = [' "$$(wc -c < build/bootsec.bin)"; \
	   od -An -tu1 -v build/bootsec.bin | awk '{ for (i = 1; i <= NF; i++) printf "%s,", $$i }'; \
	   printf '];\n'; \
	   printf 'export const stage2: [%s]u8 = [' "$$(wc -c < build/stage2.bin)"; \
	   od -An -tu1 -v build/stage2.bin | awk '{ for (i = 1; i <= NF; i++) printf "%s,", $$i }'; \
	   printf '];\n'; } > $@

# Each named program is built from its own directory against the shared runtime.
build/elf_%: $(USER_SRCS)
	@mkdir -p build
	cd userland/prog/$* && HAREPATH=$(CURDIR)/userland $(HARE) build -F -a$(ARCH) -o $(CURDIR)/build/elf_$*

build/prog_%.bin: build/elf_%
	$(OBJCOPY) -O binary $< $@

# The C runtime that cross-compiled programs link against. It is freestanding:
# no host libc, no host stack protector (its canary read would fault on an
# unset %fs), and no SSE, since we do not hand the process an FPU state.
# Symbols are hidden: a static library has nothing to interpose, and hiding
# them lets the compiler inside Bunix turn its calls into direct ones instead of
# routing every one through a PLT that expects a dynamic linker to fill in.
C_RT_DIR = userland/rt
C_RT_CFLAGS = -ffreestanding -nostdlib -fno-pic -fno-pie -fno-builtin \
	-fno-stack-protector -mno-red-zone -mfpmath=sse -O2 -fvisibility=hidden
C_RT_SRCS = crt0.S cstart.c setjmp.S heap.c string.c stdio.c posix.c initfini.c \
	ctype.c math.c stdlib.c scan.c stubs.c
# Every object depends on the headers. They define the syscall ABI, so an
# object left behind from an older header silently keeps the old calling
# convention, which is close enough to look right and wrong at run time.
C_RT_HDRS = $(wildcard $(C_RT_DIR)/*.h) $(wildcard $(C_RT_DIR)/sys/*.h)
C_RT_OBJS = $(patsubst %,build/rt/%.o,$(basename $(C_RT_SRCS)))

build/rt/%.o: $(C_RT_DIR)/%.c $(C_RT_HDRS)
	@mkdir -p build/rt
	$(CC) $(C_RT_CFLAGS) -I$(C_RT_DIR) -c $< -o $@

build/rt/%.o: $(C_RT_DIR)/%.S $(C_RT_HDRS)
	@mkdir -p build/rt
	$(CC) $(C_RT_CFLAGS) -c $< -o $@

$(C_RT_DIR)/libc.a: $(C_RT_OBJS)
	$(AR) rcs $@ $(C_RT_OBJS)

# The startup objects and the runtime library are folded into the kernel as byte
# tables. They are generated from the build rather than carried in the tree, so
# that a rebuilt libc can never be left shadowed by a stale copy of its own
# bytes: the compiler inside Bunix was once reading an embedded archive that
# silently trailed the real one.
CRT_STAGE = build/crt
RT_STAGE = build/lib

build/crt/crt1.o: $(C_RT_DIR)/crt0.S tools/bcc/bcc
	@mkdir -p $(CRT_STAGE)
	./tools/bcc/bcc -c -o $@ $<

build/crt/crti.o: $(C_RT_DIR)/crti.S
	@mkdir -p $(CRT_STAGE)
	$(CC) -c $< -o $@

build/crt/crtn.o: $(C_RT_DIR)/crtn.S
	@mkdir -p $(CRT_STAGE)
	$(CC) -c $< -o $@

user/crt.ha: build/crt/crt1.o build/crt/crti.o build/crt/crtn.o tools/embed.py
	python3 tools/embed.py $(CRT_STAGE) $@ crt

user/libc.ha: $(C_RT_DIR)/libc.a tools/embed.py
	@rm -rf $(RT_STAGE)
	@mkdir -p $(RT_STAGE)
	cp $(C_RT_DIR)/libc.a $(RT_STAGE)/libc.a
	python3 tools/embed.py $(RT_STAGE) $@ libc

# C programs: bcc compiles and links against the runtime above, producing a real
# ELF at 0x400000 whose __image_end covers .bss as well as text and data.
define C_PROG_RULE
build/elf_$(1): tools/bcc/$(1).c $(C_RT_DIR)/libc.a tools/bcc/bcc
	@mkdir -p build
	./tools/bcc/bcc -o $$@ $$<

build/prog_$(1).bin: build/elf_$(1)
	$(OBJCOPY) -O binary $$< $$@
endef
$(foreach p,$(C_PROGS),$(eval $(call C_PROG_RULE,$(p))))

# tcc is a program with sources of its own. Upstream builds it as one
# translation unit (ONE_SOURCE in its config.h), so a single bcc invocation is
# all it takes. Its own headers come first, then the runtime's. Every one of
# its sources is a prerequisite: tcc.c #includes the rest, so a Makefile that
# only watched tcc.c would keep a stale compiler after an edit anywhere else.
TCC_DIR = tools/tcc
TCC_SRCS = $(wildcard $(TCC_DIR)/*.c) $(wildcard $(TCC_DIR)/*.h)
# The runtime's headers come first: bcc compiles tcc with the host
# compiler, which has a correct va_list of its own.
TCC_CFLAGS = -I$(C_RT_DIR) -I$(CURDIR)/$(TCC_DIR) -I$(CURDIR)/$(TCC_DIR)/include

build/elf_tcc: $(TCC_SRCS) $(C_RT_DIR)/libc.a tools/bcc/bcc
	@mkdir -p build
	./tools/bcc/bcc $(TCC_CFLAGS) -o $@ tools/tcc/tcc.c

build/prog_tcc.bin: build/elf_tcc
	$(OBJCOPY) -O binary $< $@

# Fold the program images into the kernel: their bytes end to end in one blob,
# with a table naming each one's offset and size.
build/progs.bin: $(PROG_BINS)
	cat $(PROG_BINS) > $@

user/progs.s: build/progs.bin
	@{ printf '.section .rodata\n.global user.blobs\nuser.blobs:\n.incbin "build/progs.bin"\n'; } > $@

user/progs.ha: build/progs.bin $(PROG_ELFS)
	@{ printf 'export type program = struct {\n\tnam: str,\n\toff: size,\n\tbytes: size,\n\tend: u64,\n\tentry: u64,\n};\n\n'; \
	   printf 'export @symbol("user.blobs") const blobs: u8;\n\n'; \
	   printf 'export const programs: [%s]program = [\n' "$$(echo $(PROGS) | wc -w)"; \
	   off=0; \
	   for p in $(PROGS); do \
	     n=$$(wc -c < build/prog_$$p.bin); \
	     x=$$(nm build/elf_$$p | awk '$$3 == "__image_end" { print $$1 }'); \
	     e=$$(nm build/elf_$$p | awk '$$3 == "_start" { print $$1 }'); \
	     printf '\tprogram { nam = "%s", off = %s, bytes = %s, end = 0x%s, entry = 0x%s },\n' "$$p" "$$off" "$$n" "$$x" "$$e"; \
	     off=$$((off + n)); \
	   done; \
	   printf '];\n'; } > $@

run: bunix.bin
	$(QEMU) -m 256 -kernel bunix.bin -serial stdio

run-nographic: bunix.bin
	$(QEMU) -m 256 -kernel bunix.bin -display none -serial stdio

clean:
	rm -rf bunix bunix.bin build user/blob.ha user/progs.ha user/progs.s \
	user/bootsec.ha

.PHONY: all run run-nographic clean

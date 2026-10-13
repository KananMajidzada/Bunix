.POSIX:
.SUFFIXES:
.SECONDARY:

include config.mk

SRCS = $(shell find . -name '*.ha' -o -name '*.s' -o -name '*.sc')

# Programs that get an image of their own. The shell runs them by name.
# Each one ends up as both a real ELF (for nm, to read _start and __image_end)
# and a flat blob (the bytes the loader copies into user memory).
PROGS = hello wc grep cp cc test_c tcc

# Programs written in Hare, built by the Hare compiler.
HARE_PROGS = $(filter-out $(C_PROGS),$(PROGS))
# Programs written in C, cross-compiled on the host by bcc.
C_PROGS = test_c

PROG_ELFS = $(addprefix build/elf_,$(PROGS))
PROG_BINS = $(addprefix build/prog_,$(addsuffix .bin,$(PROGS)))

all: bunix.bin

# The kernel is a freestanding Hare program. HAREPATH is pointed at the tree
# itself so the build only sees our runtime and modules.
bunix: user/blob.ha user/progs.ha user/progs.s user/hdrs.ha user/src.ha $(SRCS)
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

# The compiler's own headers, served from /usr/include inside the filesystem.
user/hdrs.ha: $(wildcard $(TCC_DIR)/include/*.h) tools/embed.py
	python3 tools/embed.py $(TCC_DIR)/include $@ header

user/src.ha: $(wildcard $(TCC_DIR)/examples/*.c) tools/embed.py
	python3 tools/embed.py $(TCC_DIR)/examples $@ src

# Each named program is built from its own directory against the shared runtime.
build/elf_%: $(USER_SRCS)
	@mkdir -p build
	cd userland/prog/$* && HAREPATH=$(CURDIR)/userland $(HARE) build -F -a$(ARCH) -o $(CURDIR)/build/elf_$*

build/prog_%.bin: build/elf_%
	$(OBJCOPY) -O binary $< $@

# The C runtime that cross-compiled programs link against. It is freestanding:
# no host libc, no host stack protector (its canary read would fault on an
# unset %fs), and no SSE, since we do not hand the process an FPU state.
C_RT_DIR = userland/rt
C_RT_CFLAGS = -ffreestanding -nostdlib -fno-pic -fno-pie -fno-builtin \
	-fno-stack-protector -mno-red-zone -mfpmath=sse -O2
C_RT_SRCS = crt0.S cstart.c setjmp.S heap.c string.c stdio.c posix.c \
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
# all it takes. Its own headers come first, then the runtime's.
TCC_DIR = tools/tcc
# The runtime's headers come first: bcc compiles tcc with the host
# compiler, which has a correct va_list of its own.
TCC_CFLAGS = -I$(C_RT_DIR) -I$(CURDIR)/$(TCC_DIR) -I$(CURDIR)/$(TCC_DIR)/include

build/elf_tcc: $(TCC_DIR)/tcc.c $(C_RT_DIR)/libc.a tools/bcc/bcc
	@mkdir -p build
	./tools/bcc/bcc $(TCC_CFLAGS) -o $@ $<

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
	rm -rf bunix bunix.bin build user/blob.ha user/progs.ha user/progs.s

.PHONY: all run run-nographic clean

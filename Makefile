.POSIX:
.SUFFIXES:
.SECONDARY:

include config.mk

SRCS = $(shell find . -name '*.ha' -o -name '*.s' -o -name '*.sc')

# Programs that get an image of their own. The shell runs them by name.
PROGS = hello wc grep cp cc test_c
PROG_ELFS = $(addprefix build/elf_,$(filter-out test_c,$(PROGS)))
PROG_BINS = $(addprefix build/prog_,$(addsuffix .bin,$(PROGS)))

all: bunix.bin

# The kernel is a freestanding Hare program. HAREPATH is pointed at the tree
# itself so the build only sees our runtime and modules.
bunix: user/blob.ha user/progs.ha user/progs.s $(SRCS)
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

# Each named program is built from its own directory against the shared runtime.
build/elf_%: $(USER_SRCS)
	@mkdir -p build
	cd userland/prog/$* && HAREPATH=$(CURDIR)/userland $(HARE) build -F -a$(ARCH) -o $(CURDIR)/build/elf_$*

build/prog_%.bin: build/elf_%
	$(OBJCOPY) -O binary $< $@

# test_c is cross-compiled with bcc; copy its binary and create a minimal ELF for nm
build/prog_test_c.bin: build/test_c.bin
	cp $< $@

build/elf_test_c: build/test_c.bin
	@mkdir -p build
	@# Create a minimal ELF with __image_end symbol for the progs.ha generator
	@# The binary is linked at 0x400000; __image_end = 0x400000 + size
	@size=$$(wc -c < build/test_c.bin); \
	end=$$(printf "0x%x" $$((0x400000 + $$size))); \
	echo "SECTIONS { . = 0x400000; __image_end = $$end; }" | $(LD) -T /dev/stdin -o $@ /dev/null

# Fold the program images into the kernel: their bytes end to end in one blob,
# with a table naming each one's offset and size.
build/progs.bin: $(PROG_BINS)
	cat $(PROG_BINS) > $@

user/progs.s: build/progs.bin
	@{ printf '.section .rodata\n.global user.blobs\nuser.blobs:\n.incbin "build/progs.bin"\n'; } > $@

user/progs.ha: build/progs.bin $(PROG_ELFS) build/elf_test_c
	@{ printf 'export type program = struct {\n\tnam: str,\n\toff: size,\n\tbytes: size,\n\tend: u64,\n\tentry: u64,\n};\n\n'; \
	   printf 'export @symbol("user.blobs") const blobs: u8;\n\n'; \
	   printf 'export const programs: [%s]program = [\n' "$$(echo $(PROGS) | wc -w)"; \
	   off=0; \
	   for p in $(PROGS); do \
	     n=$$(wc -c < build/prog_$$p.bin); \
	     x=$$(nm build/elf_$$p 2>/dev/null | awk '$$3 == "__image_end" { print $$1 }'); \
	     e=$$(nm build/elf_$$p 2>/dev/null | awk '$$3 == "_start" { print $$1 }'); \
	     if [ -z "$$e" ]; then e="400000"; fi; \
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

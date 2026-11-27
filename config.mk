# Bunix build configuration.

HARE = hare
HAREC = harec
QBE = qbe
AS = as
LD = ld
OBJCOPY = objcopy
AR = ar

# Host C compiler. Used to build the freestanding C runtime that cross-compiled
# Bunix programs link against, and by bcc to do the actual compiling.
CC = cc

# Target architecture. Only x86_64 is implemented.
ARCH = x86_64

# The program that takes over the screen at boot. The boot command line can
# override this with wm=/other, and make can override it with BOOT_WM=/other.
BOOT_WM = /wm

# The build in ~/.local/bin has only the "none" display and "wav" audio
# backends, so it cannot open a window or play through the host's speakers.
# The system QEMU has gtk/sdl and pulseaudio; use it for `make run`.
QEMU = /usr/bin/qemu-system-x86_64

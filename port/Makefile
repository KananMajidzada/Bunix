# Port environment build

HAREPATH=..
Hare := hare
Harec := harec

LIBRARY_SRCS := \
	libc/syscalls.ha \
	libc/string.ha \
	libc/stdio.ha

SHELL_SRCS := \
	shell/main.ha

CC_SRCS := \
	cc/main.ha

LIBRARY_OBJS := $(LIBRARY_SRCS:.ha=.o)
SHELL_OBJS := $(SHELL_SRCS:.ha=.o)
CC_OBJS := $(CC_SRCS:.ha=.o)

all: libport.a bsh bcc

libport.a: $(LIBRARY_OBJS)
	HAREPATH=.. $(Hare) build -o $@ $(LIBRARY_SRCS)

bsh: $(SHELL_OBJS) libport.a
	HAREPATH=.. $(Hare) build -o $@ shell/main.ha

bcc: $(CC_OBJS) libport.a
	HAREPATH=.. $(Hare) build -o $@ cc/main.ha

%.o: %.ha
	HAREPATH=.. $(Harec) -o $@ $<

clean:
	rm -f *.o *.a bsh bcc

install: all
	mkdir -p ../../bin
	cp bsh bcc ../../bin/

.PHONY: all clean install
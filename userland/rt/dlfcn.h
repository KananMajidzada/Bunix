// dlfcn.h - the dynamic loader interface.
//
// Bunix has no shared objects and no dynamic loader. These entry points exist
// so a program that references them builds; each one reports that it could not
// do the thing rather than quietly succeeding.

#ifndef BUNIX_DLFCN_H
#define BUNIX_DLFCN_H

#define RTLD_LAZY    0x00001
#define RTLD_NOW     0x00002
#define RTLD_BINDING_MASK 0x3
#define RTLD_NOLOAD  0x00004
#define RTLD_GLOBAL  0x00100
#define RTLD_LOCAL   0
#define RTLD_NODELETE 0x01000
#define RTLD_NEXT    ((void *) -1)
#define RTLD_DEFAULT ((void *) -2)

void *dlopen(const char *file, int mode);
int dlclose(void *handle);
void *dlsym(void *handle, const char *name);
char *dlerror(void);

#endif
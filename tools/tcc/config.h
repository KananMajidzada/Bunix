/* config.h - build settings for TinyCC running inside Bunix.
 *
 * The compiler is a self-contained program: it reads a source file, parses it
 * and writes an object or an executable. Nothing here points at a host path,
 * so the same binary behaves the same wherever it is booted.
 */
#ifndef TCC_CONFIG_H
#define TCC_CONFIG_H

#define TCC_VERSION "0.9.27-bunix"

/* Everything lives in one translation unit, which is how upstream ships it. */
#define ONE_SOURCE 1

/* The standard headers are compiled in, so the include search list only needs
   to cover a program's own headers. */
#define CONFIG_TCC_SYSINCLUDEPATHS ""

#define CONFIG_TCC_ELFINTERP ""
#define CONFIG_TCC_CRTPREFIX ""
#define CONFIG_TCC_LIBPATHS ""
#define CONFIG_MULTIARCH_TRIPLET ""
#define CONFIG_TCC_SYSROOT ""
#define CONFIG_TCC_TRIPLET ""

#define TCC_TARGET_X86_64 1
#define TCC_VERSION_DATE "2026"

#endif
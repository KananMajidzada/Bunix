// Port environment: POSIX-compatible C types and constants

export type size = uintptr;
export type ssize = int;
export type pid_t = int;
export type uid_t = int;
export type gid_t = int;
export type mode_t = int;
export type off_t = int;
export type time_t = int;
export type clock_t = int;
export type dev_t = int;
export type ino_t = int;
export type nlink_t = int;
export type blksize_t = int;
export type blkcnt_t = int;
export type sigset_t = int;
export type siginfo_t = int;
export type sigaction = int;
export type fd_set = int;
export type timeval = int;
export type timespec = int;
export type rusage = int;
export type rlimit = int;
export type dirent = int;

export const O_RDONLY: int = 0;
export const O_WRONLY: int = 1;
export const O_RDWR: int = 2;
export const O_CREAT: int = 0x40;
export const O_EXCL: int = 0x80;
export const O_TRUNC: int = 0x200;
export const O_APPEND: int = 0x400;
export const O_NONBLOCK: int = 0x800;

export const SEEK_SET: int = 0;
export const SEEK_CUR: int = 1;
export const SEEK_END: int = 2;

export const PROT_READ: int = 1;
export const PROT_WRITE: int = 2;
export const PROT_EXEC: int = 4;
export const PROT_NONE: int = 0;

export const MAP_SHARED: int = 1;
export const MAP_PRIVATE: int = 2;
export const MAP_FIXED: int = 0x10;
export const MAP_ANONYMOUS: int = 0x20;

export const POLLIN: int = 1;
export const POLLOUT: int = 4;
export const POLLERR: int = 8;
export const POLLHUP: int = 0x10;
export const POLLNVAL: int = 0x20;

export const SIGHUP: int = 1;
export const SIGINT: int = 2;
export const SIGQUIT: int = 3;
export const SIGILL: int = 4;
export const SIGTRAP: int = 5;
export const SIGABRT: int = 6;
export const SIGBUS: int = 7;
export const SIGFPE: int = 8;
export const SIGKILL: int = 9;
export const SIGUSR1: int = 10;
export const SIGSEGV: int = 11;
export const SIGUSR2: int = 12;
export const SIGPIPE: int = 13;
export const SIGALRM: int = 14;
export const SIGTERM: int = 15;
export const SIGCHLD: int = 17;
export const SIGCONT: int = 18;
export const SIGSTOP: int = 19;
export const SIGTSTP: int = 20;
export const SIGTTIN: int = 21;
export const SIGTTOU: int = 22;

export const ENOENT: int = 2;
export const EIO: int = 5;
export const EBADF: int = 9;
export const EAGAIN: int = 11;
export const ENOMEM: int = 12;
export const EACCES: int = 13;
export const EFAULT: int = 14;
export const EBUSY: int = 16;
export const EEXIST: int = 17;
export const ENODEV: int = 19;
export const ENOTDIR: int = 20;
export const EISDIR: int = 21;
export const EINVAL: int = 22;
export const ENFILE: int = 23;
export const EMFILE: int = 24;
export const ENOTTY: int = 25;
export const EFBIG: int = 27;
export const ENOSPC: int = 28;
export const ESPIPE: int = 29;
export const EROFS: int = 30;
export const EMLINK: int = 31;
export const EPIPE: int = 32;
export const EDOM: int = 33;
export const ERANGE: int = 34;

export const STDIN_FILENO: int = 0;
export const STDOUT_FILENO: int = 1;
export const STDERR_FILENO: int = 2;

export const F_DUPFD: int = 0;
export const F_GETFD: int = 1;
export const F_SETFD: int = 2;
export const F_GETFL: int = 3;
export const F_SETFL: int = 4;
export const FD_CLOEXEC: int = 1;

export const S_IFMT: int = 0xF000;
export const S_IFSOCK: int = 0xC000;
export const S_IFLNK: int = 0xA000;
export const S_IFREG: int = 0x8000;
export const S_IFBLK: int = 0x6000;
export const S_IFDIR: int = 0x4000;
export const S_IFCHR: int = 0x2000;
export const S_IFIFO: int = 0x1000;

export const S_IRWXU: int = 0x1C0;
export const S_IRUSR: int = 0x100;
export const S_IWUSR: int = 0x80;
export const S_IXUSR: int = 0x40;
export const S_IRWXG: int = 0x38;
export const S_IRGRP: int = 0x20;
export const S_IWGRP: int = 0x10;
export const S_IXGRP: int = 0x08;
export const S_IRWXO: int = 0x07;
export const S_IROTH: int = 0x04;
export const S_IWOTH: int = 0x02;
export const S_IXOTH: int = 0x01;
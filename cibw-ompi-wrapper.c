#include <libgen.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#if defined(__FreeBSD__)
#include <sys/sysctl.h>
#endif

#define STRINGIZE_(arg) #arg
#define STRINGIZE(arg)  STRINGIZE_(arg)

#if !defined(WRAPPER)
#define WRAPPER opal_wrapper
#endif

int main(int argc, char *argv[]) {

  char exe[PATH_MAX+32];
  char path[PATH_MAX+32];
  char prefix[PATH_MAX+32];

#if defined(__APPLE__)
  uint32_t size = PATH_MAX;
  (void) _NSGetExecutablePath(exe, &size);
#elif defined(__FreeBSD__)
  size_t size = PATH_MAX;
  int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_PATHNAME, -1};
  (void) sysctl(mib, 4, path, &size, NULL, 0);
#elif defined(__DragonFly__) || defined(__NetBSD__)
  (void) readlink("/proc/curproc/file", exe, PATH_MAX);
#elif defined(__linux__)
  (void) readlink("/proc/self/exe", exe, PATH_MAX);
#elif defined(__sun)
  (void) strncpy(exe, getexecname(), PATH_MAX);
#else
# error unknown system
#endif

  (void) strncpy(path, dirname(exe), PATH_MAX);
  (void) strncat(path, "/..", PATH_MAX);
  (void) realpath(path, prefix);

  (void) setenv("OPAL_PREFIX", prefix, 1);

  (void) strncpy(exe, prefix, PATH_MAX);
  (void) strncat(exe, "/bin/", PATH_MAX);
  (void) strncat(exe, STRINGIZE(WRAPPER), PATH_MAX);

  return execv(exe, argv);
}

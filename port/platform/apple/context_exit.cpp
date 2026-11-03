// Boost.Context's Mach-O make_fcontext finishes a context whose entry function
// returned by calling __exit (the spelling in Boost's macOS assembly). iOS
// declares _exit only, so provide the symbol the unchanged assembly expects.
//
// The scheduler's entry functions call std::terminate() before returning, so
// this path is a safety net, not part of normal operation.
#include <unistd.h>

extern "C" void __exit(int status) {
    _exit(status);
}

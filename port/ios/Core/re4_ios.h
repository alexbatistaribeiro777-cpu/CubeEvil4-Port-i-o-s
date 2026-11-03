/*
 * CubeEvil4 iOS - C interface between the UIKit/Swift shell and the game core.
 *
 * The Android port talks to the core through JNI (port/android-decomp/app/src/main/cpp/
 * android_bridge.cpp). On iOS there is no JVM, so the same responsibilities are exposed
 * here as a plain C ABI that Swift can call through the bridging header.
 *
 * Right now only the stub in re4_ios_stub.c implements this file: the app builds, imports
 * discs and brings up an OpenGL ES 3 context, but no game code is linked yet. When the core
 * is ported (see ../docs/core-integration.md), re4_ios_stub.c is replaced by a real
 * Objective-C++ adapter and this header stays the stable contract.
 */

#ifndef RE4_IOS_H
#define RE4_IOS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define RE4_IOS_ABI_VERSION 1

enum {
    RE4_OK = 0,
    RE4_ERR_UNAVAILABLE = -1,
    RE4_ERR_ARGUMENT = -2,
    RE4_ERR_ALREADY_RUNNING = -3,
    RE4_ERR_START_FAILED = -4
};

/*
 * GameCube pad buttons, mirroring the bits the Android bridge forwards to pad.cpp.
 *
 * Kept as an anonymous enum on purpose: Swift imports anonymous C enum constants as
 * plain integers, while a named enum would be imported as a struct and would need
 * `.rawValue` at every use site.
 */
enum {
    RE4_PAD_A = 1u << 0,
    RE4_PAD_B = 1u << 1,
    RE4_PAD_X = 1u << 2,
    RE4_PAD_Y = 1u << 3,
    RE4_PAD_START = 1u << 4,
    RE4_PAD_L = 1u << 5,
    RE4_PAD_R = 1u << 6,
    RE4_PAD_Z = 1u << 7,
    RE4_PAD_UP = 1u << 8,
    RE4_PAD_DOWN = 1u << 9,
    RE4_PAD_LEFT = 1u << 10,
    RE4_PAD_RIGHT = 1u << 11
};

typedef struct Re4PadState {
    uint16_t buttons;
    int8_t stickX;   /* main stick, -127..127 */
    int8_t stickY;   /* main stick, -127..127 (up is positive) */
    int8_t cStickX;  /* C stick, -127..127 */
    int8_t cStickY;  /* C stick, -127..127 */
    int8_t triggerL; /* 0..127 */
    int8_t triggerR; /* 0..127 */
} Re4PadState;

int re4_ios_abi_version(void);

/* False until the real core is linked in. */
bool re4_core_is_available(void);

const char *re4_core_version(void);

/*
 * disc1Path / disc2Path point at files copied into the app's Documents folder by DiscStore.
 * dataDir is a writable directory for the memory card, shader cache and logs.
 * Returns RE4_OK or one of the RE4_ERR_* codes above.
 */
int re4_core_start(const char *disc1Path, const char *disc2Path, const char *dataDir);
void re4_core_stop(void);
bool re4_core_is_running(void);

/* Called once per CADisplayLink tick. deltaSeconds is clamped by the caller. */
void re4_core_frame(double deltaSeconds);

/* Called whenever the EAGL drawable changes size. */
void re4_core_set_viewport(int32_t width, int32_t height);

/* Called once per frame with the current controller status. May be NULL. */
void re4_core_set_pad(const Re4PadState *pad);

/*
 * Pulls interleaved float32 audio from the core.
 * Returns the number of frames written (0 means silence).
 */
uint32_t re4_core_read_audio(float *interleaved, uint32_t frames, uint32_t channels);

const char *re4_core_last_error(void);

/* level: 0 = debug, 1 = info, 2 = warning, 3 = error. */
void re4_core_set_log_handler(void (*handler)(int level, const char *message));

#ifdef __cplusplus
}
#endif

#endif /* RE4_IOS_H */

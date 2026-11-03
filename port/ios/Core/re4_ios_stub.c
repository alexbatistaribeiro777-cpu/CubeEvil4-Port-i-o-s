/*
 * Placeholder implementation of the CubeEvil4 iOS core ABI.
 *
 * It keeps the iOS shell linkable and testable before the C/C++ core is ported to Darwin.
 * The UI reports exactly this state to the user ("nucleo ainda nao integrado") instead of
 * pretending to start the game.
 *
 * Replace this file with a real adapter once the steps in ../docs/core-integration.md are
 * done; the header re4_ios.h must not change.
 */

#include "re4_ios.h"

#include <stddef.h>
#include <stdio.h>
#include <string.h>

static char g_lastError[512] =
    "O nucleo do jogo ainda nao foi integrado a esta base iOS. "
    "Veja port/ios/docs/core-integration.md.";
static bool g_running = false;
static void (*g_logHandler)(int level, const char *message) = NULL;

static void set_error(const char *message) {
    if (message == NULL) {
        g_lastError[0] = '\0';
        return;
    }
    snprintf(g_lastError, sizeof(g_lastError), "%s", message);
}

static void log_message(int level, const char *message) {
    if (g_logHandler != NULL) {
        g_logHandler(level, message);
    }
}

int re4_ios_abi_version(void) {
    return RE4_IOS_ABI_VERSION;
}

bool re4_core_is_available(void) {
    return false;
}

const char *re4_core_version(void) {
    return "CubeEvil4 iOS 0.1.0 (core not linked)";
}

int re4_core_start(const char *disc1Path, const char *disc2Path, const char *dataDir) {
    if (disc1Path == NULL || disc2Path == NULL || dataDir == NULL) {
        set_error("Discos ou diretorio de dados ausentes.");
        return RE4_ERR_ARGUMENT;
    }
    if (g_running) {
        return RE4_ERR_ALREADY_RUNNING;
    }
    log_message(2, "re4_core_start chamado, mas o core ainda nao esta integrado.");
    set_error("O nucleo do jogo ainda nao foi integrado a esta base iOS. "
              "Veja port/ios/docs/core-integration.md.");
    return RE4_ERR_UNAVAILABLE;
}

void re4_core_stop(void) {
    g_running = false;
}

bool re4_core_is_running(void) {
    return g_running;
}

void re4_core_frame(double deltaSeconds) {
    (void)deltaSeconds;
}

void re4_core_set_viewport(int32_t width, int32_t height) {
    (void)width;
    (void)height;
}

void re4_core_set_pad(const Re4PadState *pad) {
    (void)pad;
}

uint32_t re4_core_read_audio(float *interleaved, uint32_t frames, uint32_t channels) {
    (void)interleaved;
    (void)frames;
    (void)channels;
    return 0;
}

const char *re4_core_last_error(void) {
    return g_lastError;
}

void re4_core_set_log_handler(void (*handler)(int level, const char *message)) {
    g_logHandler = handler;
}

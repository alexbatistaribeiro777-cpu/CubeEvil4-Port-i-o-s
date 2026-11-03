# Integrar o núcleo do jogo ao app iOS

Este documento é o mapa técnico para transformar a base em um port jogável.
Ele assume o fork atual (`Andiweli/CubeEvil4-Android`) e cita os arquivos reais.

> Resumo: o app iOS já existe e o CI já entrega um `.ipa`; o que falta é compilar
> `port/whole` para Darwin/arm64, substituir as partes específicas de Android
> (JNI, `/proc`, `android_dlopen_ext`, link ELF) e portar a camada de UI.

## 1. Por que não é só "recompilar"

O port Android não usa JNI só como cola: ele depende de escolhas do linker ELF e
do sistema de arquivos do Linux/Android.

| Peça | Android hoje | iOS precisa |
| --- | --- | --- |
| Núcleo | `libre4_main.so` + 114 `libre4_<mod>.so` carregados com `android_dlopen_ext` | `dlopen` de dylibs embutidas **ou** link estático de todos os módulos |
| Trampolins entre módulos | assembly ELF gerado por `port/tools/whole_link_plan.py --arch arm64` | adaptar o assembly para Mach-O (`.section __TEXT,__text`) ou gerar chamadas C |
| Símbolos | `-Wl,--version-script`, `-Wl,--no-undefined`, `-Wl,-Bsymbolic`, `-Wl,--wrap` | `-exported_symbols_list`, `-Wl,-undefined,error`, `-Wl,-flat_namespace`/aliases |
| Linker | `-fuse-ld=lld` | `ld64`/`ld-prime` do Xcode |
| MEM1 em `0x80000000` | `mmap(MAP_FIXED_NOREPLACE)` | igual, mas o binário iOS precisa de `__PAGEZERO` pequeno (ver §4) |
| Espaço abaixo de 4 GB | `/proc/self/maps` + `mmap` | enumerar com `mach_vm_region`; `vm_allocate`/`mmap` fixo |
| Processo separado (`core_ipc`, `re4_coreproc`) | `fork`/`exec`, `memfd_create`, futex | **proibido no iOS**; usar só o caminho in-process |
| Log | `__android_log_vprint` | `os_log`/`fprintf` |
| Áudio | `AudioTrack` Java + JNI | `AVAudioEngine` (já preparado em `AudioEngine.swift`) |
| Vídeo | `GLSurfaceView` + JNI | `CAEAGLLayer` (já preparado em `GameGLView.swift`) |
| UI/menus | ~75 mil linhas de Java | Swift/UIKit, incremental |
| Discos | `content://` + importador Java | `UIDocumentPicker` + cópia (já feito em `DiscStore.swift`) |

## 2. Contrato que já existe

O núcleo já expõe uma API C pensada para embedders em
`port/whole/runtime/re4_core.h`, usada pelo app Android via `dlsym`:

```c
re4_core_reserve(dataDir, moduleDir); // MEM1, pastas, checagem de endereço
re4_core_start();                     // jogo numa thread própria
re4_core_state();
re4_core_message();
re4_core_pad(&pad);                   // Re4CorePad
re4_core_rumble();
re4_core_audio(int16_t *out, int frames); // 32 kHz estéreo
re4_core_audio4 / re4_core_audio6;
re4_core_card_*;                      // memory card
re4_core_pause, re4_core_debug_menu, re4_core_set_cheats, ...
```

O adapter iOS deve chamar isso diretamente e **não** tentar portar
`android_bridge.cpp` (290 KB de JNI + lógica de Activity). O arquivo
`Core/re4_ios_stub.c` é o lugar onde esse adapter entra; `Core/re4_ios.h` é o
contrato que o Swift já usa.

O renderer do Android (`port/android-decomp/app/src/main/cpp/gx_gl.cpp`, GLES 3)
consome chunks de `re4_gx_frame.h` com:

```c
const Re4GxChunk *c;
while ((c = re4_core_gx_acquire()) != NULL) { run(c); re4_core_gx_release(c); }
```

Ele não depende de JNI para desenhar (só de log e de `gettid`); é o candidato
natural a ser compilado dentro do app iOS e alimentado pelo `CADisplayLink`.

## 3. Fases de trabalho

### Fase 1 — Build system e scheduler

1. Criar `port/ios/cmake/ios.toolchain.cmake`:

   ```cmake
   set(CMAKE_SYSTEM_NAME iOS)
   set(CMAKE_OSX_ARCHITECTURES arm64)
   set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
   set(CMAKE_OSX_SYSROOT iphoneos)
   set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)
   ```

2. Em `port/whole/CMakeLists.txt`, trata `CMAKE_SYSTEM_NAME STREQUAL "iOS"` como
   o caso Android nas partes que não são de linker (por exemplo `_FILE_OFFSET_BITS`
   não existe no Darwin).

3. Scheduler: `port/src/stack_context.cpp` só aceita Windows, Android e Linux
   ARM. Adicionar um ramo `__APPLE__` usando Boost.Context Mach-O:
   - copiar `make_arm64_aapcs_macho_gas.S` e `jump_arm64_aapcs_macho_gas.S` do
     Boost.Context 1.88 para `port/third_party/boost_context/`;
   - incluir no `port/cmake/ContextSources.cmake` um caso `APPLE AND arm64`;
   - em `stack_context.cpp`, incluir `<sys/mman.h>`, `<unistd.h>` e declarar
     `jump_fcontext`/`make_fcontext` no ramo `__APPLE__`;
   - atenção: no iOS `pthread_attr_setstack`/`mmap` abaixo de 4 GB depende do
     `__PAGEZERO` (ver §4).

4. O alvo `re4_host` (launcher Linux) não existe no iOS. O entry point é o app.

### Fase 2 — Serviços do runtime

| Arquivo | Mudança |
| --- | --- |
| `port/whole/runtime/log.cpp` | `#ifdef __ANDROID__` → `#ifdef __APPLE__` com `os_log` ou `fprintf(stderr)`. Manter o ring buffer e o arquivo de log. |
| `port/whole/runtime/mem1.cpp` | `MAP_FIXED_NOREPLACE` não existe no Darwin; definir como `MAP_FIXED` no Apple. Manter a checagem de `p == want`. |
| `port/whole/runtime/game_window.cpp` | `/proc/self/maps` não existe. Trocar a enumeração por `mach_vm_region`/`vm_region_64` + `vm_allocate` com `VM_FLAGS_FIXED`. Reservar a janela abaixo de 4 GB. |
| `port/whole/runtime/module_loader.cpp` | Remover `android_dlext.h`/`android_dlopen_ext`. Para dylibs, `dlopen(path, RTLD_NOW | RTLD_LOCAL)`. Para link estático, trocar a tabela por ponteiros diretos. |
| `port/whole/runtime/core_ipc.cpp`, `core_ipc_client.cpp` | Não compilar no iOS (`memfd_create`, futex, socketpair de processo). O app iOS roda o núcleo no próprio processo. |
| `port/whole/runtime/core_api.cpp` | Revisar `pthread_setname_np` (assinatura difere), `re4_module_window_reserve` (só 32 bits), `dladdr` (existe no Darwin) e `re4_window_map`. |
| `port/whole/runtime/os_thread.cpp` | Conferir o ramo não-Android: `pthread_setname_np` no Darwin recebe só o nome. |
| `port/whole/runtime/dvd.cpp`, `dsp.cpp`, `pad.cpp`, `memcard.cpp` | Devem ser POSIX; validar includes e `off_t`. |
| `port/whole/runtime/re4_core.h` | Reaproveitar como está; é a API do adapter. |

O `re4_core_reserve` já checa se `libre4_main` está abaixo de `0x80000000` e falha
com mensagem — isso ajuda a diagnosticar o layout no iOS.

### Fase 3 — Renderer

1. Compilar `port/android-decomp/app/src/main/cpp/gx_gl.cpp`,
   `gx_gl_shader.cpp`, `gx_texture.cpp`, `gx_stream.cpp` e os arquivos
   `*_gl.cpp` necessários no alvo iOS.
2. Substituir `android/log.h` por um `re4_log`/`os_log`.
3. Substituir `syscall(SYS_gettid)` por `pthread_threadid_np(NULL, &tid)`.
4. No `GameGLView`, depois de criar o `EAGLContext`, chamar o init do renderer;
   a cada frame, drenar `re4_core_gx_acquire()` antes de `presentRenderbuffer`.
5. GLES 3 é o mesmo no iOS, mas os shaders e extensões precisam ser testados
   (o Android usa `GL_EXT` de forma opcional; ver `gx_gl.cpp`).
6. Alternativa de longo prazo: um backend Metal lendo `re4_gx_frame.h`.

### Fase 4 — Áudio

O núcleo entrega PCM 16 bits (32 kHz estéreo) por `re4_core_audio`. O
`AudioEngine.swift` atual usa float32 e chama `re4_core_read_audio`; trocar a
ponte para produzir `int16` e converter para float, ou mudar o contrato em
`re4_ios.h`. Também portar:

- `port/whole/runtime/dsp.cpp` (mixer/DSP) — já é C++ puro;
- `re4_core_audio4/audio6` se quiser Dolby Pro Logic II;
- volume, música e efeitos (`sound_*.cpp` no app Android).

### Fase 5 — Input e toque

- O `ControllerManager.swift` já mapeia GameController para `Re4PadState`.
  Alinhar os bits com `Re4CorePad` (`re4_core.h` usa os bits do SDK: A 0x0100,
  B 0x0200 etc.), ou converter no adapter.
- Toque: o app Android tem `CoreTouch.java`, `TouchControls.java`,
  `menu_touch.cpp`, `qte_touch.cpp`, `knife_swipe.cpp`, `gyro.cpp`. Portar
  primeiro o básico (stick virtual + botões A/B/X/Y/L/R/Z/START) e depois
  gyro, swipe da faca, QTE e inventory touch.
- Vibração: `CoreHaptics` no lugar de `Vibrator`.

### Fase 6 — Menus, saves e dados

- Menus do app (`CoreMenu.java` 75 KB, `StartupActivity.java` 27 KB,
  `GameMenuArt.java`, `InventoryDialog.java` etc.): reescrever em SwiftUI/UIKit.
  Começar pelo essencial: importar discos, iniciar, configurações de vídeo,
  áudio e controles.
- Memory card: `re4_core_card_*` já é C; a UI de exportar/importar `.gci` pode
  usar `UIDocumentPicker`.
- Saves: `save_native.cpp`, `save_game.cpp`, `gci.cpp` são portáveis.
- O menu de debug do jogo é código do próprio jogo e vem junto com o núcleo.

### Fase 7 — Empacotamento

- O workflow atual gera IPA sem assinatura. Para assinatura automática com conta
  paga, adicionar secrets:
  `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `PROVISIONING_PROFILE_BASE64`,
  `DEVELOPMENT_TEAM`, e usar `xcodebuild -exportArchive` com
  `ExportOptions.plist`.
- Enquanto o núcleo não estiver pronto, o app continua sendo um shell útil para
  validar GL, importação e controles no iPhone.

## 4. O bloqueio do `__PAGEZERO` (importante)

Apps iOS de 64 bits têm um segmento `__PAGEZERO` cobrindo `0x0..0x100000000`
(4 GB) para pegar ponteiros nulos. O jogo precisa de MEM1 em `0x80000000` e de
stacks/estruturas abaixo de 4 GB (o código guarda endereços de 32 bits).

Solução usada por emuladores no iOS: linkar o app com `__PAGEZERO` de 4 KB:

```sh
-Wl,-pagezero_size,0x1000
```

No Xcode, isso vai em `OTHER_LDFLAGS` (ou `MACHO_PAGEZERO_SIZE`). Depois disso,
`mmap(0x80000000, ..., MAP_FIXED)` e `vm_allocate` na faixa baixa passam a ser
possíveis, desde que a faixa esteja livre. Testar em aparelho real: o dyld e o
próprio iOS podem ocupar partes da faixa; `game_window.cpp` precisa descobrir
buracos de forma dinâmica (equivalente ao `/proc/self/maps`).

Se isso não funcionar, a alternativa é reescrever as partes do jogo que guardam
ponteiros em 32 bits — muito mais invasivo (o port Android gastou vários
documentos só nisso, ver `port/docs/`).

## 5. Riscos e limites

- **Memória:** o port Android pede ~4 GB de RAM; iPhones com 4 GB podem receber
  jetsam ao carregar as texturas em 1080p. O menu Android já tem "Potato mode",
  resolução dinâmica e cache de shaders; portar isso cedo.
- **OpenGL ES:** funciona, mas está depreciado. Um port futuro para Metal é
  desejável, não obrigatório para sideload.
- **Assinatura:** dylibs embutidas precisam ser assinadas junto com o app. Se o
  Sideloadly re-assinar só o binário principal, os módulos podem falhar; por
  isso o link estático é mais seguro no iOS.
- **Sem `fork`/JIT:** o iOS não permite criar processos nem memória executável
  dinâmica. O núcleo já é código nativo compilado (não é emulador PPC), então
  não precisa de JIT; só o `core_ipc` precisa sair.
- **Sandbox:** o app só vê o próprio contêiner. A cópia dos discos para
  `Documents` já resolve isso.
- **App Store:** não é possível distribuir (IP da Capcom/Nintendo/CRI). Somente
  sideload.

## 6. Ordem recomendada de PRs

1. `port/ios` (este PR): shell + CI.
2. Toolchain iOS + scheduler arm64 (compila um executável de teste que troca de
   contexto).
3. Runtime mínimo: log, MEM1, `re4_core_reserve` + `re4_core_start` com dados
   reais, sem renderer (logs no console).
4. Scheduler + jogo rodando a primeira sala em modo headless.
5. Renderer GLES 3 no `GameGLView`.
6. Áudio.
7. Controles/toque.
8. Menus e saves.
9. Assinatura/entrega contínua.

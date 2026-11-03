# CubeEvil4 para iOS — base do port

Este diretório contém a **base do port para iOS** do CubeEvil4 (o port Android do
protótipo de Resident Evil 4 de GameCube). Ela compila um app iOS de verdade e um
`.ipa` não assinado no GitHub Actions, mas **o núcleo do jogo ainda não está
linkado**: ao tocar em "Iniciar jogo" o app explica exatamente isso.

> O repositório não inclui dados do jogo. Você precisa das suas próprias imagens
> dos dois discos (ISO/GCM/RVZ). Veja a seção legal no fim.

## Estado atual

| Área | Estado |
| --- | --- |
| App iOS (UIKit, iOS 15+, arm64) | Funciona |
| Pipeline GitHub Actions (macOS) → `.ipa` não assinado | Funciona |
| Contexto OpenGL ES 3 + `CADisplayLink` + viewport | Funciona |
| Importação dos discos 1 e 2 (cópia para Documents, validação ISO/GCM/RVZ) | Funciona |
| Detecção de controle (GameController) e mapeamento para o pad | Funciona |
| `AVAudioEngine` com puxada de PCM do core | Pronto, mudo enquanto o core não existe |
| ABI C estável entre Swift e o core (`Core/re4_ios.h`) | Definida |
| Núcleo C/C++ do jogo (renderer, áudio, menus, saves) | **Não integrado** |
| Fase 1: núcleo `port/` compilado para iOS arm64 (`libre4.a`) | Pipeline pronto; ver `ios-core.yml` |

O caminho para integrar o núcleo (e por que ele é grande) está em
[`docs/core-integration.md`](docs/core-integration.md).

## Estrutura

```
port/ios/
├── project.yml                  # especificação do projeto (XcodeGen)
├── Info.plist                   # bundle, orientação, Files, launch screen
├── CubeEvil4/                   # app Swift
│   ├── AppDelegate.swift
│   ├── GameViewController.swift # tela inicial, importação dos discos
│   ├── GameGLView.swift         # EAGL + OpenGL ES 3 + display link
│   ├── DiscStore.swift          # cópia/validação das imagens
│   ├── ControllerManager.swift  # GameController -> Re4PadState
│   ├── AudioEngine.swift        # AVAudioEngine <- re4_core_read_audio
│   └── Assets.xcassets/
├── Core/                        # contrato C com o núcleo
│   ├── re4_ios.h
│   └── re4_ios_stub.c           # implementação provisória
├── cmake/ios.toolchain.cmake    # CMake para o SDK de dispositivo (arm64)
├── scripts/build-unsigned-ipa.sh
├── scripts/build-ios-core.sh    # núcleo -> build/ios-core/libre4.a
└── docs/core-integration.md     # plano técnico do port do núcleo
```

O `.xcodeproj` é gerado pelo XcodeGen e não é versionado.

## Como gerar o IPA no GitHub Actions

1. Faça o push deste fork para o GitHub (o repositório precisa ter Actions habilitado).
2. Abra **Actions → iOS build → Run workflow**.
3. Ao terminar, baixe o artifact **`CubeEvil4-ios-unsigned`**.
4. Assine e instale no iPhone com uma conta Apple gratuita.

O workflow roda em `macos-15-intel` (Xcode 16) e executa
`port/ios/scripts/build-unsigned-ipa.sh`. Ele usa `CODE_SIGNING_ALLOWED=NO`, então
não precisa de certificado nem de segredo no repositório.

### Instalar no iPhone com Apple ID gratuito

O `.ipa` sai **sem assinatura**. Use uma ferramenta de sideload:

- **Sideloadly** (Windows/macOS) ou **AltStore/AltStore PAL**;
- entre com seu Apple ID gratuito;
- o app vale **7 dias** por assinatura e você pode ter no máximo 3 apps
  assinados ao mesmo tempo;
- depois de instalar, no iPhone vá em **Ajustes → Geral → VPN e Gerenciamento
  de Dispositivos** e confie no seu certificado de desenvolvedor;
- para renovar, repita o sideload.

Limitações da conta gratuita: sem entitlements especiais, 7 dias de validade e
necessidade de re-assinar. Para distribuição contínua, o caminho é a conta paga
do Apple Developer Program (aí dá para configurar certificado e provisioning
profile como secrets no Actions).

> O identificador do bundle é `com.cubeevil4.ios` em `project.yml`. Se o
> Sideloadly reclamar de conflito, troque por algo único, por exemplo
> `com.seunome.cubeevil4`.

## Núcleo iOS — Fase 1 (`libre4.a`)

O núcleo portado (`port/`) já compila para **iOS arm64** como uma biblioteca
estática. Isso valida o toolchain, o scheduler e as partes independentes de
Android; o app ainda não linka essa biblioteca.

O workflow [`.github/workflows/ios-core.yml`](../../../.github/workflows/ios-core.yml)
roda em `macos-15-intel` e publica o artifact **`libre4-ios-arm64`**:

```sh
bash port/ios/scripts/build-ios-core.sh
# saída: build/ios-core/libre4.a
lipo -archs build/ios-core/libre4.a   # arm64
nm -gU build/ios-core/libre4.a | grep fcontext
```

O que entra no archive agora:

- `re4_scheduler` + `re4_original` (scheduler do port);
- Boost.Context **Mach-O arm64** (`make/jump_arm64_aapcs_macho_gas.S`);
- `re4_loader`, `re4_modules`, `re4_game_runtime`, `re4_gx`, `re4_yz2`,
  `re4_async_file`, `re4_asset_index` (o núcleo portado, sem o `port/whole`).

O que ainda **não** entra: `port/whole` (main.dol + 114 módulos REL), o runtime
de MEM1/DVD/GX e o renderer. Isso é a Fase 2 em diante; os erros reais de
compilação para o SDK iOS aparecem no log do workflow.

## Build local (macOS)

```sh
brew install xcodegen
cd port/ios
xcodegen generate
open CubeEvil4.xcodeproj
```

Ou gere o IPA direto:

```sh
bash port/ios/scripts/build-unsigned-ipa.sh
# saída: port/ios/build/ipa/CubeEvil4-unsigned.ipa
```

No Mac você também pode rodar no simulador (sem assinatura):

```sh
xcodebuild -project CubeEvil4.xcodeproj -scheme CubeEvil4 \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## O que o app faz hoje

- Sobe em paisagem, tela cheia, com um contexto OpenGL ES 3 e um frame escuro
  animado — prova de que o caminho gráfico do port funciona no iOS.
- Pede **Disco 1** e **Disco 2** pelo seletor de arquivos, copia para
  `Documents/Discs/` (fora do backup do iCloud), valida o magic de GameCube em
  `0x1C` (`C2 33 9F 3D`) ou o container RVZ, e mostra o game ID e o tamanho.
- Detecta controles Bluetooth/USB via GameController e converte para
  `Re4PadState` (bits em `Core/re4_ios.h`).
- Prepara o `AVAudioEngine` com um `AVAudioSourceNode` que puxa PCM float32
  intercalado de `re4_core_read_audio`.
- Expõe o contrato C que o adaptador do núcleo vai implementar:
  `re4_core_start`, `re4_core_frame`, `re4_core_set_pad`,
  `re4_core_set_viewport`, `re4_core_read_audio`, `re4_core_stop`.

## O que falta

Praticamente todo o jogo:

- compilar o núcleo (`port/whole`) para Darwin/arm64;
- substituir o linker ELF/trampolines por equivalentes Mach-O (ou link estático);
- trocar o JNI do Android por um adaptador Objective-C++ sobre `core_api.cpp`;
- portar menus, saves, importação e controles de toque do Java para Swift;
- mapear áudio (DSP) para o `AVAudioEngine`;
- resolver as restrições de endereço do jogo (MEM1 em `0x80000000`) no iOS.

Ordem sugerida, arquivos e riscos: [`docs/core-integration.md`](docs/core-integration.md).

## Limitações e avisos

- **Somente sideload.** O projeto usa código de Capcom/Nintendo/CRI e não pode
  ir para a App Store. Não há dados do jogo no repositório.
- **iOS 15+, arm64.** Não há build para 32 bits nem para simulador como alvo
  principal.
- **OpenGL ES está depreciado** no iOS, mas ainda disponível. Um port futuro
  pode trocar o renderer por Metal; o código atual usa GLES 3 porque o renderer
  do port Android já é GLES 3.
- **Memória:** o jogo espera um GameCube (24 MB de MEM1 + ARAM). O port Android
  precisa de ~4 GB de RAM; iPhones com 4 GB ou menos podem sofrer com o jetsam
  do iOS quando o núcleo for integrado.
- **Conta gratuita:** o IPA expira em 7 dias.

## Legal

CubeEvil4 é um projeto de fã, sem afiliação com Capcom, Nintendo ou CRI
Middleware. Resident Evil é marca da Capcom. O código descompilado pertence aos
seus donos e é publicado para pesquisa e preservação. Este diretório não contém
nem distribui dados do jogo.

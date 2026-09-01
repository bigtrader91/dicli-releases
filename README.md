# dicli v0.4.1 무료 프리뷰

dicli는 Claude Code, Codex, Antigravity 세션 로그를 읽어 개발 용어를
한국어로 설명하는 읽기 전용 터미널 사전입니다. 이 저장소는 소스 저장소가
아니라 5인 파일럿용 무료 실행 파일과 설치 프로그램만 제공합니다.

## 설치

GitHub 계정, GitHub CLI, Rust, 소스 체크아웃은 필요하지 않습니다.

### Linux x86_64

Linux x86_64용이며 관리자 권한이나 별도 시스템 패키지 없이 사용자 디렉터리에
설치하도록 구성되어 있습니다.

```bash
curl --fail --location --remote-name \
  https://github.com/bigtrader91/dicli-releases/releases/download/v0.4.1/dicli-install-v0.4.1.sh
bash dicli-install-v0.4.1.sh
"$HOME/.local/bin/dicli" demo
```

`curl`이 없으면 [v0.4.1 릴리스](https://github.com/bigtrader91/dicli-releases/releases/tag/v0.4.1)에서 아래 세 파일을 브라우저로 같은 폴더에 받습니다.

- `dicli-install-v0.4.1.sh`
- `dicli-v0.4.1-linux-x86_64.tar.gz`
- `dicli-v0.4.1-linux-x86_64.tar.gz.sha256`

그 폴더에서 네트워크를 쓰지 않는 로컬 검증 모드로 설치합니다.

```bash
mkdir -p "$HOME/.local/bin"
bash dicli-install-v0.4.1.sh \
  --asset-dir . \
  --install-dir "$HOME/.local/bin" \
  --target linux-x86_64
"$HOME/.local/bin/dicli" demo
```

### Windows x86_64

Windows PowerShell에서 실행합니다. `-ExecutionPolicy Bypass`는 이 설치
프로세스에만 적용되며 관리자 권한을 부여하거나 정책을 영구 변경하지 않습니다.

```powershell
Invoke-WebRequest -UseBasicParsing `
  -Uri https://github.com/bigtrader91/dicli-releases/releases/download/v0.4.1/dicli-install-v0.4.1.ps1 `
  -OutFile dicli-install-v0.4.1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\dicli-install-v0.4.1.ps1
& "$env:LOCALAPPDATA\dicli\bin\dicli.exe" demo
```

`VCRUNTIME140.dll` 오류가 나오면 Microsoft의 최신 Visual C++
Redistributable x64를 설치한 뒤 다시 실행하세요:
<https://aka.ms/vc14/vc_redist.x64.exe>

### macOS

동일한 Bash 설치 프로그램이 Apple Silicon arm64와 Intel x86_64를
자동으로 구분합니다. macOS 파일은 CI 프리뷰이며 아직 실제 사용자 파일럿을
통과한 지원 대상이라고 주장하지 않습니다.

### 데스크톱 앱 (Linux·Windows)

`v0.4.1` 공개 release에는 CLI 10개 파일과 데스크톱 6개 파일을 합쳐 정확히
16개 asset이 포함됩니다. 데스크톱 asset은 Linux AppImage와 checksum 및
installer, Windows current-user NSIS setup과 checksum 및 installer입니다.
macOS 데스크톱 bundle은 이 release에 포함하지 않습니다.

Linux desktop installer:

```bash
curl --fail --location --remote-name \
  https://github.com/bigtrader91/dicli-releases/releases/download/v0.4.1/dicli-desktop-install-v0.4.1.sh
bash dicli-desktop-install-v0.4.1.sh
```

Windows desktop installer:

```powershell
Invoke-WebRequest -UseBasicParsing `
  -Uri https://github.com/bigtrader91/dicli-releases/releases/download/v0.4.1/dicli-desktop-install-v0.4.1.ps1 `
  -OutFile dicli-desktop-install-v0.4.1.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\dicli-desktop-install-v0.4.1.ps1
```

두 installer 모두 bundle checksum을 먼저 확인합니다. Linux installer는
사용자 디렉터리만 사용하고 `sudo`를 실행하지 않으며, Windows installer는
현재 사용자 범위의 NSIS 설치만 실행합니다.

## 현재 검증 경계

- 네 CLI target은 native GitHub Actions에서 build와 archive/installer smoke를 통과했고, Linux AppImage·Windows NSIS는 native build·bundle checksum 검증을 통과했습니다.
- source release와 이 공개 release의 16개 파일명·크기·SHA-256이 일치합니다.
- 로그인 없는 공개 release 페이지와 checksum 다운로드를 확인했습니다.
- persistent Ubuntu·Windows guest의 신규 설치, `demo`, 실제 세션 추적은 아직 대기 중이므로 현재 상태는 `preview`입니다.

## 설치 프로그램이 확인하는 것

- 운영체제와 CPU 대상
- 릴리스 아카이브의 SHA-256
- 정확한 아카이브 파일 목록과 파일 형식
- 임시 설치 파일의 `dicli 0.4.1` 출력
- 기존 설치를 보존하는 검증 후 원자적 교체

설치 프로그램은 `sudo`나 관리자 권한을 사용하지 않고 PATH 또는 셸 설정을
자동으로 변경하지 않으며 `dicli demo`를 자동 실행하지 않습니다.

## 첫 실행

`demo`는 계정, 네트워크, 실제 에이전트 로그 없이 CORS와 Drizzle ORM의
한국어 설명을 출력합니다.

```bash
dicli demo
dicli explain cors
```

실제 세션을 별도 터미널에서 따라가려면 프로젝트 디렉터리에서 실행합니다.

```bash
dicli --watch
```

dicli는 에이전트의 로컬 JSONL 로그를 읽기만 하며 프롬프트를 보내거나 세션을
수정하지 않습니다. 파일럿 기록에는 원문 로그, 토큰, 계정 정보 대신 설치 성공,
첫 설명까지 걸린 시간, `--watch` 실행 여부, 중단 이유, 재사용 의향만 남깁니다.

## 무료 프리뷰 범위

- 내장 BGM과 Pro 팩은 포함하지 않습니다.
- 시스템 오디오 의존성을 없애기 위해 BGM 재생 기능도 포함하지 않습니다.
- 비공개 소스 팩을 사용하는 `dicli pack update` 원격 갱신은 제공하지 않습니다.
- 결제, 구독, 계정, 지원 보장은 없습니다.
- Linux x86_64와 Windows x86_64는 공개 배포 중이지만 persistent guest 검증 전인 파일럿 프리뷰입니다.
- VM 테스트는 설치 호환성 증거일 뿐 5명의 실제 사용자에 포함되지 않습니다.

문제는 공개 저장소의 Issues에 민감정보나 에이전트 원문을 붙이지 말고 재현 절차와
오류 메시지만 남겨주세요:
<https://github.com/bigtrader91/dicli-releases/issues>

## 라이선스

dicli 배포물에는 Apache License 2.0과 잠금된 런타임 의존성의 라이선스 문구를
담은 `THIRD-PARTY-LICENSES.html`이 포함됩니다. 이 공개 저장소에는 dicli 소스
코드나 개발 Git 이력이 포함되지 않습니다.

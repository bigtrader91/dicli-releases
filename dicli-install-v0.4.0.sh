#!/usr/bin/env bash
set -euo pipefail

TAG="v0.4.0"
VERSION="0.4.0"
RELEASE_BASE_URL="https://github.com/bigtrader91/dicli-releases/releases/download/v0.4.0"
SUPPORTED_TARGETS="linux-x86_64, windows-x86_64, macos-arm64, macos-x86_64"

ASSET_DIR=""
INSTALL_DIR=""
REQUESTED_TARGET=""
ASSET_DIR_SET=0
INSTALL_DIR_SET=0
TARGET_SET=0
TEMP_DIR=""
STAGED_INSTALL=""
SUCCESS=0

die() {
    printf 'dicli installer: error: %s\n' "$1" >&2
    exit 1
}

cleanup() {
    local status=$?
    if [[ -n "$STAGED_INSTALL" && -e "$STAGED_INSTALL" ]]; then
        if ! rm -f "$STAGED_INSTALL"; then
            printf 'dicli installer: error: staged file cleanup failed: %s\n' \
                "$STAGED_INSTALL" >&2
            [[ "$status" -ne 0 ]] || status=1
        fi
    fi
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        if [[ "$SUCCESS" -eq 1 ]]; then
            if ! rm -rf "$TEMP_DIR"; then
                printf 'dicli installer: error: temporary directory cleanup failed: %s\n' \
                    "$TEMP_DIR" >&2
                [[ "$status" -ne 0 ]] || status=1
            fi
        else
            printf 'dicli installer: diagnostic files retained at %s\n' "$TEMP_DIR" >&2
        fi
    fi
    trap - EXIT
    exit "$status"
}
trap cleanup EXIT

require_option_value() {
    local option=$1
    local remaining=$2
    local value=${3-}
    if [[ "$remaining" -lt 2 || -z "$value" || "$value" == --* ]]; then
        die "missing value for $option"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --asset-dir)
            require_option_value "$1" "$#" "${2-}"
            [[ "$ASSET_DIR_SET" -eq 0 ]] || die "duplicate option --asset-dir"
            ASSET_DIR=$2
            ASSET_DIR_SET=1
            shift 2
            ;;
        --install-dir)
            require_option_value "$1" "$#" "${2-}"
            [[ "$INSTALL_DIR_SET" -eq 0 ]] || die "duplicate option --install-dir"
            INSTALL_DIR=$2
            INSTALL_DIR_SET=1
            shift 2
            ;;
        --target)
            require_option_value "$1" "$#" "${2-}"
            [[ "$TARGET_SET" -eq 0 ]] || die "duplicate option --target"
            REQUESTED_TARGET=$2
            TARGET_SET=1
            shift 2
            ;;
        *)
            die "unknown option"
            ;;
    esac
done

if [[ "$ASSET_DIR_SET" -eq 1 ]]; then
    [[ "$INSTALL_DIR_SET" -eq 1 ]] || die "--asset-dir requires --install-dir"
else
    if [[ "$INSTALL_DIR_SET" -eq 1 || "$TARGET_SET" -eq 1 ]]; then
        die "--target and --install-dir are accepted only with --asset-dir"
    fi
fi

HOST_SYSTEM=$(uname -s) || die "could not detect the operating system"
HOST_MACHINE=$(uname -m) || die "could not detect the CPU architecture"

if [[ "$TARGET_SET" -eq 1 ]]; then
    TARGET=$REQUESTED_TARGET
else
    case "$HOST_SYSTEM/$HOST_MACHINE" in
        Linux/x86_64|Linux/amd64)
            TARGET="linux-x86_64"
            ;;
        Darwin/arm64|Darwin/aarch64)
            TARGET="macos-arm64"
            ;;
        Darwin/x86_64|Darwin/amd64)
            TARGET="macos-x86_64"
            ;;
        *)
            die "unsupported platform $HOST_SYSTEM/$HOST_MACHINE; supported targets: $SUPPORTED_TARGETS"
            ;;
    esac
fi

case "$TARGET" in
    linux-x86_64|macos-arm64|macos-x86_64)
        ARCHIVE_NAME="dicli-v0.4.0-$TARGET.tar.gz"
        CHECKSUM_NAME="$ARCHIVE_NAME.sha256"
        PREFIX="dicli-v0.4.0-$TARGET"
        ;;
    *)
        die "unsupported target; supported targets: $SUPPORTED_TARGETS"
        ;;
esac

if [[ "$ASSET_DIR_SET" -eq 0 ]]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to download dicli"
fi

TEMP_ROOT=${TMPDIR:-/tmp}
TEMP_DIR=$(mktemp -d "$TEMP_ROOT/dicli-install-v0.4.0.XXXXXX") || \
    die "could not create a diagnostic temporary directory"
ARCHIVE_PATH="$TEMP_DIR/$ARCHIVE_NAME"
CHECKSUM_PATH="$TEMP_DIR/$CHECKSUM_NAME"

if [[ "$ASSET_DIR_SET" -eq 1 ]]; then
    [[ -f "$ASSET_DIR/$ARCHIVE_NAME" ]] || \
        die "missing asset: $ASSET_DIR/$ARCHIVE_NAME"
    [[ -f "$ASSET_DIR/$CHECKSUM_NAME" ]] || \
        die "missing asset: $ASSET_DIR/$CHECKSUM_NAME"
    cp "$ASSET_DIR/$ARCHIVE_NAME" "$ARCHIVE_PATH" || \
        die "could not copy asset: $ASSET_DIR/$ARCHIVE_NAME"
    cp "$ASSET_DIR/$CHECKSUM_NAME" "$CHECKSUM_PATH" || \
        die "could not copy asset: $ASSET_DIR/$CHECKSUM_NAME"
else
    curl --fail --location --silent --show-error \
        --output "$ARCHIVE_PATH" "$RELEASE_BASE_URL/$ARCHIVE_NAME" || \
        die "could not download $ARCHIVE_NAME from the public $TAG release"
    curl --fail --location --silent --show-error \
        --output "$CHECKSUM_PATH" "$RELEASE_BASE_URL/$CHECKSUM_NAME" || \
        die "could not download $CHECKSUM_NAME from the public $TAG release"
fi

EXPECTED_CHECKSUM_SIZE=$((64 + 2 + ${#ARCHIVE_NAME} + 1))
CHECKSUM_SIZE=$(wc -c < "$CHECKSUM_PATH") || die "could not read checksum file"
[[ "$CHECKSUM_SIZE" -eq "$EXPECTED_CHECKSUM_SIZE" ]] || \
    die "invalid checksum file; expected one strict ASCII line for $ARCHIVE_NAME"
IFS= read -r CHECKSUM_LINE < "$CHECKSUM_PATH" || \
    die "invalid checksum file; final LF is required"
EXPECTED_DIGEST=${CHECKSUM_LINE:0:64}
CHECKSUM_SEPARATOR=${CHECKSUM_LINE:64:2}
CHECKSUM_BASENAME=${CHECKSUM_LINE:66}
[[ "$CHECKSUM_SEPARATOR" == "  " && "$CHECKSUM_BASENAME" == "$ARCHIVE_NAME" ]] || \
    die "invalid checksum file; expected '<sha256>  $ARCHIVE_NAME'"
[[ ${#EXPECTED_DIGEST} -eq 64 ]] || die "invalid checksum digest length"
case "$EXPECTED_DIGEST" in
    *[!0-9a-f]*) die "invalid checksum digest; lowercase hexadecimal required" ;;
esac

case "$HOST_SYSTEM" in
    Linux)
        command -v sha256sum >/dev/null 2>&1 || die "sha256sum is required on Linux"
        HASH_OUTPUT=$(sha256sum "$ARCHIVE_PATH") || die "could not checksum $ARCHIVE_NAME"
        ;;
    Darwin)
        command -v shasum >/dev/null 2>&1 || die "shasum is required on macOS"
        HASH_OUTPUT=$(shasum -a 256 "$ARCHIVE_PATH") || die "could not checksum $ARCHIVE_NAME"
        ;;
    *)
        die "unsupported Unix platform $HOST_SYSTEM; supported targets: $SUPPORTED_TARGETS"
        ;;
esac
ACTUAL_DIGEST=${HASH_OUTPUT%% *}
[[ "$ACTUAL_DIGEST" == "$EXPECTED_DIGEST" ]] || \
    die "checksum mismatch for $ARCHIVE_NAME"

EXPECTED_MEMBERS=$(printf '%s\n' \
    "$PREFIX/" \
    "$PREFIX/LICENSE" \
    "$PREFIX/README.md" \
    "$PREFIX/THIRD-PARTY-LICENSES.html" \
    "$PREFIX/dicli")
ACTUAL_MEMBERS=$(tar -tzf "$ARCHIVE_PATH") || die "could not inspect archive members"
[[ "$ACTUAL_MEMBERS" == "$EXPECTED_MEMBERS" ]] || \
    die "archive members differ from the required exact set"

RAW_TAR="$TEMP_DIR/archive.tar"
gzip -dc "$ARCHIVE_PATH" > "$RAW_TAR" || die "could not decompress archive for type validation"
RAW_HEADER="$TEMP_DIR/archive-header.bin"
RAW_BLOCK=0
validate_raw_header() {
    local expected_name=$1
    local expected_type=$2
    local header_size
    local member_name
    local member_prefix
    local member_type
    local size_field
    local member_size

    dd if="$RAW_TAR" of="$RAW_HEADER" bs=512 skip="$RAW_BLOCK" count=1 2>/dev/null || \
        die "could not read raw archive header for $expected_name"
    header_size=$(wc -c < "$RAW_HEADER") || die "could not size raw archive header"
    [[ "$header_size" -eq 512 ]] || die "archive header is truncated for $expected_name"
    member_name=$(dd if="$RAW_HEADER" bs=1 count=100 2>/dev/null | tr -d '\000')
    member_prefix=$(dd if="$RAW_HEADER" bs=1 skip=345 count=155 2>/dev/null | tr -d '\000')
    member_type=$(od -An -t u1 -j 156 -N 1 "$RAW_HEADER" | tr -d '[:space:]')
    size_field=$(dd if="$RAW_HEADER" bs=1 skip=124 count=12 2>/dev/null | tr -d '\000 ')

    [[ "$member_name" == "$expected_name" && -z "$member_prefix" ]] || \
        die "archive raw member name differs from the required path: $expected_name"
    [[ "$member_type" == "$expected_type" ]] || \
        die "archive raw member type differs from the required exact type: $expected_name"
    [[ -n "$size_field" ]] || die "archive member size is missing: $expected_name"
    case "$size_field" in
        *[!0-7]*) die "archive member size is not strict octal: $expected_name" ;;
    esac
    member_size=$((8#$size_field))
    RAW_BLOCK=$((RAW_BLOCK + 1 + (member_size + 511) / 512))
}

validate_raw_header "$PREFIX/" 53
validate_raw_header "$PREFIX/LICENSE" 48
validate_raw_header "$PREFIX/README.md" 48
validate_raw_header "$PREFIX/THIRD-PARTY-LICENSES.html" 48
validate_raw_header "$PREFIX/dicli" 48
dd if="$RAW_TAR" of="$RAW_HEADER" bs=512 skip="$RAW_BLOCK" count=1 2>/dev/null || \
    die "could not read archive end marker"
END_HEADER_SIZE=$(wc -c < "$RAW_HEADER") || die "could not size archive end marker"
END_HEADER_NONZERO=$(tr -d '\000' < "$RAW_HEADER" | wc -c) || \
    die "could not validate archive end marker"
[[ "$END_HEADER_SIZE" -eq 512 && "$END_HEADER_NONZERO" -eq 0 ]] || \
    die "archive contains an unexpected raw header after the required members"

if [[ "$ASSET_DIR_SET" -eq 0 ]]; then
    INSTALL_DIR="$HOME/.local/bin"
fi
mkdir -p "$INSTALL_DIR" || die "could not create install directory: $INSTALL_DIR"
INSTALL_DIR=$(cd "$INSTALL_DIR" && pwd -P) || \
    die "could not resolve install directory: $INSTALL_DIR"
DESTINATION="$INSTALL_DIR/dicli"

if [[ -L "$DESTINATION" || (-e "$DESTINATION" && ! -f "$DESTINATION") ]]; then
    die "install destination must be a regular file or absent: $DESTINATION"
fi

if [[ -x "$DESTINATION" ]]; then
    EXISTING_VERSION=$("$DESTINATION" --version 2>&1 || true)
    printf 'Existing dicli at %s: %s\n' "$DESTINATION" "$EXISTING_VERSION"
fi

STAGED_INSTALL=$(mktemp "$INSTALL_DIR/.dicli-install-v0.4.0.XXXXXX") || \
    die "could not create an atomic install stage in $INSTALL_DIR"
tar -xOzf "$ARCHIVE_PATH" "$PREFIX/dicli" > "$STAGED_INSTALL" || \
    die "could not stream the validated dicli binary from $ARCHIVE_NAME"
chmod 0755 "$STAGED_INSTALL" || die "could not make the staged binary executable"

VERSION_STDOUT="$TEMP_DIR/version.stdout"
VERSION_STDERR="$TEMP_DIR/version.stderr"
if ! "$STAGED_INSTALL" --version > "$VERSION_STDOUT" 2> "$VERSION_STDERR"; then
    cat "$VERSION_STDERR" >&2 || true
    if [[ "$TARGET" == "linux-x86_64" ]] && \
        grep -Fq "libasound.so.2" "$VERSION_STDERR"; then
        die "Linux runtime dependency libasound.so.2 is missing; install your distribution's ALSA runtime package (Ubuntu 24.04: libasound2t64), then retry"
    fi
    die "staged dicli --version failed"
fi
VERSION_SIZE=$(wc -c < "$VERSION_STDOUT") || die "could not read staged version output"
IFS= read -r VERSION_LINE < "$VERSION_STDOUT" || die "staged version output needs a final LF"
[[ "$VERSION_SIZE" -eq 12 && "$VERSION_LINE" == "dicli $VERSION" ]] || \
    die "staged version mismatch; expected exactly 'dicli $VERSION'"

mv -f "$STAGED_INSTALL" "$DESTINATION" || \
    die "could not atomically install dicli at $DESTINATION"
STAGED_INSTALL=""

printf 'Installed dicli %s at %s\n' "$VERSION" "$DESTINATION"
PATH_READY=0
OLD_IFS=$IFS
IFS=:
for PATH_ENTRY in ${PATH:-}; do
    if [[ "$PATH_ENTRY" == "$INSTALL_DIR" ]]; then
        PATH_READY=1
        break
    fi
done
IFS=$OLD_IFS

printf 'Manual next command:\n'
if [[ "$PATH_READY" -eq 1 ]]; then
    printf '  dicli demo\n'
else
    printf '  %q demo\n' "$DESTINATION"
    printf 'To use dicli by name in this shell:\n'
    printf '  export PATH=%q:"$PATH"\n' "$INSTALL_DIR"
fi

SUCCESS=1

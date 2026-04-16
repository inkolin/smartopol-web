#!/bin/sh
set -eu

# Smartopol installer
# Usage: curl -sSf https://get.smartopol.ai/install.sh | sh

MANIFEST_URL="https://updates.smartopol.ai/versions.json"
INSTALL_DIR="$HOME/.local/bin"
BIN_NAME="smartopol"

main() {
    need_cmd curl
    need_cmd tar
    need_cmd uname

    local _arch _os _target _version _url _sha256 _tmpdir

    _os="$(uname -s)"
    _arch="$(uname -m)"

    case "$_os" in
        Linux)
            case "$_arch" in
                x86_64)  _target="x86_64-unknown-linux-gnu" ;;
                aarch64) _target="aarch64-unknown-linux-gnu" ;;
                arm64)   _target="aarch64-unknown-linux-gnu" ;;
                *)       err "Unsupported architecture: $_arch" ;;
            esac
            ;;
        Darwin)
            case "$_arch" in
                x86_64)  _target="x86_64-apple-darwin" ;;
                arm64)   _target="aarch64-apple-darwin" ;;
                aarch64) _target="aarch64-apple-darwin" ;;
                *)       err "Unsupported architecture: $_arch" ;;
            esac
            ;;
        *)
            if [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSLENV:-}" ]; then
                case "$_arch" in
                    x86_64)  _target="x86_64-unknown-linux-gnu" ;;
                    aarch64) _target="aarch64-unknown-linux-gnu" ;;
                    *)       err "Unsupported architecture: $_arch" ;;
                esac
            else
                err "Unsupported OS: $_os. Use WSL on Windows: https://learn.microsoft.com/windows/wsl/install"
            fi
            ;;
    esac

    say "Detecting platform: $_target"

    say "Fetching latest version..."
    local _manifest
    _manifest="$(curl -sSf "$MANIFEST_URL")" || err "Failed to fetch version manifest"

    _version="$(printf '%s' "$_manifest" | grep -o '"stable":"[^"]*"' | head -1 | cut -d'"' -f4)"
    if [ -z "$_version" ]; then
        err "Could not determine latest version"
    fi

    say "Latest version: $_version"

    _url="$(printf '%s' "$_manifest" | grep -o "\"${_target}\":{[^}]*}" | grep -o '"url":"[^"]*"' | cut -d'"' -f4)"
    if [ -z "$_url" ]; then
        err "No build available for $_target"
    fi

    _sha256="$(printf '%s' "$_manifest" | grep -o "\"${_target}\":{[^}]*}" | grep -o '"sha256":"[^"]*"' | cut -d'"' -f4)"

    _tmpdir="$(mktemp -d)"
    trap "rm -rf '$_tmpdir'" EXIT

    say "Downloading smartopol $_version..."
    curl -sSfL "$_url" -o "$_tmpdir/smartopol.tar.gz" || err "Download failed"

    if [ -n "$_sha256" ]; then
        say "Verifying checksum..."
        local _actual
        if command -v sha256sum > /dev/null 2>&1; then
            _actual="$(sha256sum "$_tmpdir/smartopol.tar.gz" | cut -d' ' -f1)"
        elif command -v shasum > /dev/null 2>&1; then
            _actual="$(shasum -a 256 "$_tmpdir/smartopol.tar.gz" | cut -d' ' -f1)"
        else
            say "Warning: no sha256sum/shasum found, skipping verification"
            _actual="$_sha256"
        fi
        if [ "$_actual" != "$_sha256" ]; then
            err "Checksum mismatch (expected $_sha256, got $_actual)"
        fi
    fi

    say "Installing to $INSTALL_DIR/$BIN_NAME..."
    mkdir -p "$INSTALL_DIR"

    tar xzf "$_tmpdir/smartopol.tar.gz" -C "$_tmpdir"

    if [ -f "$_tmpdir/smartopol" ]; then
        mv "$_tmpdir/smartopol" "$INSTALL_DIR/$BIN_NAME"
    elif [ -f "$_tmpdir/$BIN_NAME" ]; then
        mv "$_tmpdir/$BIN_NAME" "$INSTALL_DIR/$BIN_NAME"
    else
        local _found
        _found="$(find "$_tmpdir" -name smartopol -type f | head -1)"
        if [ -n "$_found" ]; then
            mv "$_found" "$INSTALL_DIR/$BIN_NAME"
        else
            err "Could not find smartopol binary in archive"
        fi
    fi

    chmod +x "$INSTALL_DIR/$BIN_NAME"

    if ! echo "$PATH" | grep -q "$INSTALL_DIR"; then
        say ""
        say "Add this to your shell profile:"
        say "  export PATH=\"$INSTALL_DIR:\$PATH\""
        say ""
    fi

    say ""
    say "smartopol $_version installed successfully!"
    say ""

    if [ -t 0 ] && [ -t 1 ]; then
        say "Running initial setup..."
        say ""
        "$INSTALL_DIR/$BIN_NAME" setup || true
    else
        say "Run 'smartopol setup' to configure your agent."
    fi
}

say() {
    printf 'smartopol: %s\n' "$1"
}

err() {
    say "ERROR: $1" >&2
    exit 1
}

need_cmd() {
    if ! command -v "$1" > /dev/null 2>&1; then
        err "need '$1' (not found in PATH)"
    fi
}

main "$@"

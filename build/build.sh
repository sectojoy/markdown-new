#!/bin/bash
#
# Dify Plugin Build Script (Unsigned)
#
# Build unsigned .difypkg package for the current plugin project.
# This script is designed for local builds and CI release workflows.
#
# Usage:
#   ./build/build.sh [--clean]
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$SCRIPT_DIR/output"
TEMP_DIR="$SCRIPT_DIR/.temp"
MANIFEST_FILE="$ROOT_DIR/manifest.yaml"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --clean, -c    Clean build artifacts before building
  --help, -h     Show this help message
EOF
}

clean_build() {
    log_info "Cleaning build artifacts..."
    rm -rf "$TEMP_DIR"
    rm -f "$OUTPUT_DIR"/*.difypkg "$OUTPUT_DIR"/*.sha256 2>/dev/null || true
    log_info "Build artifacts cleaned"
}

require_manifest() {
    if [ ! -f "$MANIFEST_FILE" ]; then
        log_error "manifest.yaml not found: $MANIFEST_FILE"
        exit 1
    fi
}

require_dify_cli() {
    if ! command -v dify >/dev/null 2>&1; then
        log_error "dify CLI is required but not found in PATH."
        log_error "Install via Homebrew: brew tap langgenius/dify && brew install dify"
        log_error "or download binary: https://github.com/langgenius/dify-plugin-daemon/releases"
        exit 1
    fi
}

extract_manifest_value() {
    local key="$1"
    grep -m1 "^${key}:" "$MANIFEST_FILE" | cut -d: -f2- | xargs
}

copy_project_files() {
    local src_dir="$1"
    local dest_dir="$2"

    if command -v rsync >/dev/null 2>&1; then
        rsync -a \
            --exclude='.git' \
            --exclude='build/output' \
            --exclude='build/.temp' \
            --exclude='__pycache__' \
            --exclude='*.pyc' \
            --exclude='.DS_Store' \
            --exclude='.venv' \
            --exclude='venv' \
            "$src_dir/" "$dest_dir/"
    else
        cp -R "$src_dir"/. "$dest_dir"/
        rm -rf "$dest_dir/.git" "$dest_dir/build/output" "$dest_dir/build/.temp" 2>/dev/null || true
        find "$dest_dir" -name "__pycache__" -type d -prune -exec rm -rf {} + 2>/dev/null || true
        find "$dest_dir" -name "*.pyc" -type f -delete 2>/dev/null || true
        find "$dest_dir" -name ".DS_Store" -type f -delete 2>/dev/null || true
    fi
}

build_package() {
    local plugin_name="$1"
    local plugin_version="$2"
    local build_dir="$TEMP_DIR/${plugin_name}"
    local versioned_pkg="$OUTPUT_DIR/${plugin_name}-${plugin_version}.difypkg"
    local latest_pkg="$OUTPUT_DIR/${plugin_name}.difypkg"

    log_step "Building plugin package: ${plugin_name} (${plugin_version})"

    rm -rf "$build_dir"
    mkdir -p "$build_dir" "$OUTPUT_DIR"

    log_info "Copying project files..."
    copy_project_files "$ROOT_DIR" "$build_dir"

    if [ ! -f "$build_dir/manifest.yaml" ]; then
        log_error "manifest.yaml missing in build directory"
        exit 1
    fi

    # Ensure Dify-required assets directory exists.
    # If _assets/icon.svg is missing, fallback to root icon file.
    mkdir -p "$build_dir/_assets"
    if [ ! -f "$build_dir/_assets/icon.svg" ]; then
        local manifest_icon
        manifest_icon="$(grep -m1 '^icon:' "$build_dir/manifest.yaml" | cut -d: -f2- | xargs || true)"
        if [ -n "$manifest_icon" ] && [ -f "$build_dir/$manifest_icon" ]; then
            cp "$build_dir/$manifest_icon" "$build_dir/_assets/icon.svg"
            log_info "Auto-created _assets/icon.svg from $manifest_icon"
        elif [ -f "$build_dir/icon.svg" ]; then
            cp "$build_dir/icon.svg" "$build_dir/_assets/icon.svg"
            log_info "Auto-created _assets/icon.svg from icon.svg"
        else
            log_error "Missing icon asset. Expected _assets/icon.svg or a root icon file."
            exit 1
        fi
    fi

    log_info "Packaging .difypkg..."
    dify plugin package "$build_dir" -o "$versioned_pkg"

    if [ ! -f "$versioned_pkg" ]; then
        log_error "package build failed: $versioned_pkg"
        exit 1
    fi

    cp -f "$versioned_pkg" "$latest_pkg"
    shasum -a 256 "$versioned_pkg" > "${versioned_pkg}.sha256"
    shasum -a 256 "$latest_pkg" > "${latest_pkg}.sha256"

    local size
    size="$(du -h "$versioned_pkg" | cut -f1)"
    log_info "Package built: $versioned_pkg ($size)"
    log_info "Latest alias: $latest_pkg"
}

main() {
    local do_clean=false

    while [ $# -gt 0 ]; do
        case "$1" in
            --clean|-c)
                do_clean=true
                ;;
            --help|-h|help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                usage
                exit 1
                ;;
        esac
        shift
    done

    require_manifest
    require_dify_cli

    local plugin_name
    local plugin_version
    plugin_name="$(extract_manifest_value "name")"
    plugin_version="$(extract_manifest_value "version")"

    if [ -z "$plugin_name" ] || [ -z "$plugin_version" ]; then
        log_error "Failed to read 'name' or 'version' from manifest.yaml"
        exit 1
    fi

    if [ "$do_clean" = true ]; then
        clean_build
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    echo "║      Dify Plugin Build System (Unsigned Package)          ║"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""

    build_package "$plugin_name" "$plugin_version"

    echo ""
    log_info "Build completed successfully"
    log_info "Output files:"
    ls -lh "$OUTPUT_DIR"/*.difypkg "$OUTPUT_DIR"/*.sha256 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
    echo ""
}

main "$@"

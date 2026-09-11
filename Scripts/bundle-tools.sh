#!/bin/sh
#
# Build phase: put yt-dlp + a universal ffmpeg inside the .app so it is
# self-contained on any Mac (Apple Silicon and Intel) with no Homebrew.
#
# Best-effort: a failed download does not fail the build — the app then falls
# back to a system-installed yt-dlp/ffmpeg. Downloads are cached in the built
# product; clean build to refresh.

set -u

FFMPEG_TAG="b6.0"   # eugeneware/ffmpeg-static

BIN_DIR="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/bin"
mkdir -p "$BIN_DIR"

fetch() {   # url  destination  ->  0 on success
    if [ -s "$2" ]; then return 0; fi
    echo "note: downloading $(basename "$2") …"
    if curl --fail --location --retry 3 --retry-delay 2 --output "$2.part" "$1"; then
        mv "$2.part" "$2"
        return 0
    fi
    rm -f "$2.part"
    echo "warning: could not download $(basename "$2")"
    return 1
}

# --- yt-dlp: already a universal standalone binary ---------------------------
fetch "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" \
      "$BIN_DIR/yt-dlp" && chmod +x "$BIN_DIR/yt-dlp"

# --- ffmpeg: fuse the two per-arch static builds into one universal binary ---
if [ ! -s "$BIN_DIR/ffmpeg" ]; then
    ARM="$BIN_DIR/.ffmpeg-arm64"
    X64="$BIN_DIR/.ffmpeg-x86_64"
    base="https://github.com/eugeneware/ffmpeg-static/releases/download/${FFMPEG_TAG}"
    fetch "$base/ffmpeg-darwin-arm64" "$ARM" || true
    fetch "$base/ffmpeg-darwin-x64"   "$X64" || true

    if [ -s "$ARM" ] && [ -s "$X64" ]; then
        lipo -create "$ARM" "$X64" -output "$BIN_DIR/ffmpeg"
    elif [ -s "$ARM" ]; then
        cp "$ARM" "$BIN_DIR/ffmpeg"
    elif [ -s "$X64" ]; then
        cp "$X64" "$BIN_DIR/ffmpeg"
    fi
    rm -f "$ARM" "$X64"
    [ -s "$BIN_DIR/ffmpeg" ] && chmod +x "$BIN_DIR/ffmpeg"
fi

# --- every bundled binary needs a valid signature to run on Apple Silicon ----
for tool in yt-dlp ffmpeg; do
    [ -s "$BIN_DIR/$tool" ] || continue
    if ! codesign --verify --quiet "$BIN_DIR/$tool" 2>/dev/null; then
        echo "note: ad-hoc signing $tool"
        codesign --force --sign - --timestamp=none "$BIN_DIR/$tool" || true
    fi
done

echo "note: bundle-tools finished"
exit 0

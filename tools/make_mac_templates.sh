#!/bin/zsh
# Godot ships one universal macOS template. Thin it into arm64 and x86_64
# zips so single-architecture builds can be exported (set them as
# custom_template/release on the "macOS Apple Silicon" / "macOS Intel" presets).
set -e
T="$HOME/Library/Application Support/Godot/export_templates/4.7.1.stable"
OUT=${1:-$HOME/godot-mac-templates}
mkdir -p "$OUT/u" && cd "$OUT/u" && unzip -o -q "$T/macos.zip"
for arch in arm64 x86_64; do
  rm -rf "$OUT/$arch" && mkdir -p "$OUT/$arch" && cp -R macos_template.app "$OUT/$arch/"
  lipo -thin $arch macos_template.app/Contents/MacOS/godot_macos_release.universal -output "$OUT/$arch/macos_template.app/Contents/MacOS/godot_macos_release.$arch"
  rm -f "$OUT/$arch/macos_template.app/Contents/MacOS/"*.universal
  (cd "$OUT/$arch" && zip -q -r "$OUT/macos_$arch.zip" macos_template.app)
  echo "$OUT/macos_$arch.zip"
done

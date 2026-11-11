# Nerd Font icons on Termux

[English](font.md) | [中文](font.zh-CN.md)

omp draws its status line with Unicode symbols by default, so no extra font is needed. To use the Nerd Font icons,
install a Nerd Font in Termux and select the `nerd` preset.

## Font

```sh
V=MapleMono-NF
curl -fL -o "$TMPDIR/maple.zip" \
  "https://github.com/subframe7536/maple-font/releases/latest/download/$V-unhinted.zip"
unzip -o "$TMPDIR/maple.zip" -d "$TMPDIR/maple"
cp "$TMPDIR/maple/$V-Regular.ttf" ~/.termux/font.ttf
```

Set `V=MapleMono-NF-CN` for Chinese text: that variant is larger (152 MB), while the regular font has no CJK glyphs,
so Chinese falls back to the system font. Restart the Termux app afterwards. Any Nerd Font works the same way.

## Verify

```sh
printf '\uf015 \uf07b \ue0b0\n'
```

Three icons mean the font is active.

## Point omp at it

```sh
omp config set symbolPreset nerd
```

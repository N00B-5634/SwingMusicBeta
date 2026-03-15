# App icon and logo placement

## App icon (already generated)
`AppIcon.appiconset/` contains a generated placeholder icon in all
required sizes. Replace `AppIcon-1024.png` with the real 1024×1024
Swing Music icon and run:

```bash
python3 regenerate_icons.py   # (see script below)
```

Or replace all sizes manually.

## Swing Music logo (used in UI)
Drop three PNGs into `SwingLogo.imageset/`:

| File | Size | Used for |
|---|---|---|
| `swing_logo_1x.png` | 44×44 | Standard displays |
| `swing_logo_2x.png` | 88×88 | Retina displays |
| `swing_logo_3x.png` | 132×132 | Super Retina (iPhone Pro) |

Source SVGs from the Android repo:
- `uicomponent/src/main/res/drawable/swing_music_logo_outlined.xml`
- `uicomponent/src/main/res/drawable/swing_music_logo_rounded.xml`

Convert with Inkscape (available on Linux):
```bash
inkscape --export-type=png --export-width=132 \
  --export-filename=swing_logo_3x.png \
  swing_music_logo_outlined.svg
```

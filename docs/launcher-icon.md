# Launcher icon

`icon.png` is the only source artwork (1254x1254, RGB). Android needs several
different slots; a single bitmap cannot serve them correctly.

## Before

- `android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png` was the original
  1254x1254 book with a checklist and a red arrow on a navy background, copied
  unchanged into the **xxxhdpi** slot. Android therefore treated it as a
  313dp icon and downscaled it heavily for every device.
- No `mdpi`, `hdpi`, `xhdpi` or `xxhdpi` variants existed, so every density
  read the oversized xxxhdpi bitmap.
- No `mipmap-anydpi-v26` adaptive icon existed, and the manifest had no
  `roundIcon`. On API 26+ launchers the bitmap was shown as a legacy icon
  inside a white/rounded container, scaled down further, and the red arrow
  could be cropped by circular or squircle masks on some OEMs. There was no
  round-icon slot at all.

## After

`tools/generate_launcher_icons.mjs` (Node built-ins only, no ImageMagick)
regenerates every slot from `icon.png`:

| Slot | Densities | Sizes |
| --- | --- | --- |
| Legacy square `ic_launcher.png` | mdpi / hdpi / xhdpi / xxhdpi / xxxhdpi | 48 / 72 / 96 / 144 / 192 px |
| Legacy round `ic_launcher_round.png` | same | 48 / 72 / 96 / 144 / 192 px |
| Adaptive foreground `ic_launcher_foreground.png` | same | 108 / 162 / 216 / 324 / 432 px (108dp) |
| Adaptive XML | `mipmap-anydpi-v26` | `ic_launcher.xml`, `ic_launcher_round.xml` |

Adaptive geometry:

- The foreground canvas is 108dp; the visible viewport is 72dp.
- The artwork is scaled to 74dp and centred. Its farthest point (the arrow
  tip) is about 35dp from the centre, inside the 36dp visible radius, and the
  artwork's square edge (37dp from centre) falls outside the viewport, so the
  mask never shows a seam.
- The background layer is the solid colour `#082B43`
  (`@color/ic_launcher_background`), sampled from the artwork's corners.
- `AndroidManifest.xml` now declares both `android:icon` and
  `android:roundIcon`.

The generated previews used during the fix (`build/icon-preview.png`,
`icon-round-preview.png`, `icon-adaptive-preview.png`) are development
artifacts and are not committed.

## Regenerate

```bash
node tools/generate_launcher_icons.mjs            # write all slots
node tools/generate_launcher_icons.mjs --preview  # build/*.png previews only
```

The script decodes the RGB PNG, area-averages it down (never upscales), writes
8-bit PNGs, and is deterministic. Re-run it only when `icon.png` changes.

## Limitations

- No monochrome layer is provided, so Android 13 themed icons fall back to the
  coloured adaptive icon. Adding one requires a single-colour silhouette of
  the checklist.
- The adaptive result is verified from generated previews and APK builds; a
  final side-by-side on physical launchers (circle, squircle, rounded square)
  still needs a device.

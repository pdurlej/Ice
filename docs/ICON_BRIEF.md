# Fire — macOS App Icon Design Brief

App: **Fire** (a maintained fork of Ice)
Platform: macOS 14+ (Sonoma, Sequoia, Tahoe)
Bundle ID: `me.durlej.Fire`
Surface: Finder, Dock, Launchpad, About panel, Settings sidebar. (Menu-bar status item is a separate, monochrome template image — see §9.)
Reference: ASOIAF / Balerion the Black Dread (jet-black scales, red eyes, Aegon I's dragon).

---

## 1. One-line concept

A jet-black dragon's eye, slit pupil glowing molten red, on a charred-obsidian squircle.

## 2. Brand alignment — Ice → Fire

The upstream Ice icon is a **cool cobalt-blue squircle** (#2D4FB7-ish) with a **stylized 3D wireframe ice cube** in soft white/silver, lit from upper-left. It reads as "structured, clean, cold, geometric."

Fire must be its **thermal opposite** while inheriting the same iconographic grammar so the two read as siblings, not strangers:

| Axis | Ice (upstream) | Fire (this fork) |
|---|---|---|
| Hue | cool cobalt blue | warm obsidian black + ember red |
| Temperature | cold, crystalline | hot, smoldering |
| Subject | inert geometric solid (cube) | living organic detail (dragon's eye) |
| Lighting | diffused, soft highlights | high-contrast inner glow / emissive |
| Mood | calm, orderly | watchful, latent menace |

Inheritance: same Big Sur squircle silhouette, same physical canvas size, same inset margins, same "single dominant subject centered with a hint of dimensionality" treatment. A user with both apps installed should instantly see them as a pair.

## 3. Subject matter — chosen: (c) the dragon eye

**Choice: a single Balerion-style dragon eye.** Vertical slit pupil, iris in graduated red→orange ember tones, sclera in deep black with subtle scaled lid texture surrounding it. The eye fills roughly the central 70% of the canvas.

**Why the eye wins:**

- **Scales to 16px.** A single high-contrast circular shape with one vertical slit survives at the smallest icon size. Big macOS-icon principle: one read, not three.
- **Iconic and ownable.** Dragon eyes are instantly recognizable as "dragon" without depicting a literal HBO-style head — sidesteps copyright/derivative risk (see §8).
- **Inherits Ice's grammar.** Ice centers a single geometric subject inside a colored squircle. Eye does the same with an organic subject — direct visual rhyme.
- **Emotional payload.** A watchful eye in a menu-bar utility says "this app is keeping an eye on your menu bar" — on-the-nose in the best way.

**Why (a) full dragon silhouette is weaker.** At 32px and below a full dragon collapses into a black smudge. Wings, neck, tail all become illegible. It's also harder to make distinct from generic fantasy-game iconography.

**Why (b) geometric flame is weaker.** A pure flame shape reads as "fire" but doesn't carry the Balerion / ASOIAF reference at all — could be any energy/heat utility. Worse, the macOS HIG specifically warns that flame/spark glyphs read as "warning" or "trending" in system contexts, creating semantic noise.

## 4. Color palette (exact hex)

| Role | Hex | Notes |
|---|---|---|
| Background squircle — top | `#1A0E0E` | Near-black with the faintest warm undertone, so it's clearly distinct from a pure-grey Finder background |
| Background squircle — bottom | `#0A0506` | Deeper, cooler black for subtle vertical gradient — mirrors Ice's top-light gradient |
| Sclera / outer eye | `#0F0708` | Obsidian black |
| Iris outer ring | `#7A1010` | Dried-blood crimson |
| Iris mid | `#C8281A` | Ember red |
| Iris inner glow | `#FF6A1F` | Molten orange — highest-luminance pixel in the icon |
| Pupil slit | `#000000` | Pure black, full opacity |
| Scale highlights / rim light | `#3A1A1A` | Warm dark for subtle specular on lid scales |
| Optional accent — corner emissive | `#FFB347` rgba(255,179,71,0.12) | Soft cast across upper-left, mirroring Ice's upper-left light source |

Contrast: the iris vs background ΔE is ~55 — readable on both light and dark macOS Dock backgrounds. The menu-bar status item is monochrome (§9) so this palette only governs AppIcon.

## 5. Composition

- **Canvas:** 1024×1024 master, exported to all sizes.
- **Shape:** Apple Big Sur squircle. Use Apple's official `AppIcon` template (corner radius ≈ 22.37% of side length — not a CSS `border-radius`, it's a continuous-curvature superellipse). Easiest path: place artwork inside Apple's [macOS Production Templates](https://developer.apple.com/design/resources/) `.sketch`/`.figma` file or the standard Xcode "macOS App Icon" template.
- **Content inset:** ~12% margin on all sides — content lives in the central 824×824 region of the 1024 canvas. Matches Apple HIG guidance for macOS Big Sur+ icons (no full-bleed, no edge-touching elements).
- **Composition:** centered subject. Eye horizontally centered; vertical center of pupil aligned with the canvas center, optionally nudged 2–3% upward (optical center > geometric center for circular subjects).
- **Depth:** very subtle inner shadow at the squircle edge (2–3px at 1024) to suggest the eye is recessed slightly into the obsidian, not stickered on top. Mirrors the soft 3D treatment Ice gives its cube.
- **No text, no glyphs, no "F" letterform.** Apple HIG: no text in macOS app icons.

## 6. Required sizes & filenames

Per `Ice/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` — preserve filenames exactly so `Contents.json` does not need to change. Plus one App Store master.

| Size (px) | Scale | Logical pt | Filename |
|---|---|---|---|
| 16×16 | 1x | 16 | `icon_16x16.png` |
| 32×32 | 2x | 16 | `icon_16x16@2x.png` |
| 32×32 | 1x | 32 | `icon_32x32.png` |
| 64×64 | 2x | 32 | `icon_32x32@2x.png` |
| 128×128 | 1x | 128 | `icon_128x128.png` |
| 256×256 | 2x | 128 | `icon_128x128@2x.png` |
| 256×256 | 1x | 256 | `icon_256x256.png` |
| 512×512 | 2x | 256 | `icon_256x256@2x.png` |
| 512×512 | 1x | 512 | `icon_512x512.png` |
| 1024×1024 | 2x | 512 | `icon_512x512@2x.png` |
| 1024×1024 | — | — | `icon_1024x1024.png` (App Store master / archival; not referenced in `Contents.json`) |

That's **10 files referenced by Contents.json** + **1 archival master = 11 PNGs total**.

Best practice: hand-tune the 16×16 and 32×32 (and their @2x) renders rather than naively downscaling. At those sizes the pupil slit may need to be thickened 1px and the iris simplified to two color stops, otherwise the eye becomes a brown dot. Generate from the 1024 master, then manually re-export the smallest four with adjusted line weights.

## 7. Generation prompts

### a. Midjourney v6+ (single line, paste as-is)

```
A macOS Big Sur app icon, centered close-up of a black dragon's eye with vertical slit pupil and a molten red-orange iris glowing from within, set inside a rounded-square obsidian black tile with a soft vertical gradient and a faint warm light from the upper left, subtle scaled eyelid texture in deep crimson, flat vector illustration, clean edges, no text, no logo, app icon style --style raw --ar 1:1 --stylize 200 --v 6.1
```

### b. DALL-E 3 / Imagen 3 (descriptive)

```
A macOS application icon, square format with rounded-corner (squircle) edges. The background is a deep obsidian black with a subtle vertical gradient from #1A0E0E at the top to #0A0506 at the bottom. Centered on the tile is a single stylized dragon's eye in close-up: vertical slit pupil in pure black, surrounded by a glowing ember-red iris that fades from dark crimson (#7A1010) at the edge to bright molten orange (#FF6A1F) near the pupil. The sclera and surrounding lid show faint dark-red scaled texture. Soft warm light catches the upper-left edge. Flat, clean vector illustration suitable for an app icon. No text, no letters, no border. Transparent area outside the squircle.
```

## 8. Rejection criteria — reject the render if any of these apply

1. **Illegible at 16×16.** Squint test: if the pupil disappears or the iris reads as a brown blob, reject.
2. **Photorealistic / textured render.** macOS icons are stylized illustrations. Skin pores, hyperreal reflections, ray-traced refraction → reject. Aim for Apple's "Maps app" or "Reminders app" level of stylization, not concept art.
3. **HBO House of the Dragon / Game of Thrones derivative.** No imagery that resembles Drogon, Vhagar, Caraxes, or any on-screen show design. Generic-dragon visual language only.
4. **Wrong canvas shape.** If the corners are CSS-style circular (constant-radius) rather than continuous-curvature squircle, reject — it will look obviously non-Apple next to other Dock icons.
5. **Content too close to the edge.** Less than ~10% margin → reject. Looks crowded next to system icons.
6. **Off-palette colors.** Pink, purple, or yellow-dominant. Must read as black + red, not "rainbow dragon."
7. **Multiple subjects.** Two eyes, eye + flame, eye + dragon head, etc. Single subject only.
8. **Embedded text or glyphs.** No "F", no "Fire" wordmark, no runes. Apple HIG forbids text in app icons.
9. **Asymmetric pupil placement** that doesn't optically center. Test by viewing in the Dock at actual size.
10. **JPEG artifacts, visible compression, or non-transparent backgrounds outside the squircle.** PNG-32 only.

## 9. Alternative monochrome variant — menu-bar status item

macOS auto-derives a tinted menu-bar glyph from a template image, but the eye is too visually busy to template well. Ship a **purpose-drawn template PNG** instead, registered with `image.isTemplate = true`:

- **Subject:** a simplified dragon-eye silhouette — a vertical lens shape (almond outline) with a thick vertical slit pupil in the center. Pure black on transparent background.
- **Canvas:** 22×22 pt logical, exported at 1x/2x/3x (22, 44, 66 px wide).
- **Stroke:** 2px @1x for the almond outline, 3px @1x for the pupil slit, so the slit dominates at 22px.
- **Optical weight:** matches Apple's SF Symbols `eye.fill` weight ≈ **Regular**. The system tints it white (dark menu bar) or black (light menu bar) automatically; supplying it as a template guarantees correct tint in all macOS appearances and the new Accent Color tinting in Sequoia/Tahoe.
- Filename suggestion: `MenuBarIcon.imageset/` with `MenuBarIcon.png`, `MenuBarIcon@2x.png`, `MenuBarIcon@3x.png`, and `Contents.json` flag `"template-rendering-intent": "template"`.

If a "hidden / showing" state needs to be communicated (Ice has this), supply a second template glyph: same almond, **pupil closed to a thin horizontal line** = hidden state. Same eye, eye-shut.

## 10. Delivery format

- **File format:** PNG-32 (RGBA, 8 bits per channel), **transparent background** outside the squircle. Not JPEG, not WebP, not HEIC, not SVG-in-Xcassets.
- **Color profile:** sRGB IEC61966-2.1, embedded. Display P3 also acceptable for the @2x renders if hand-tuned.
- **One file per size**, named exactly per the table in §6.
- **No interlacing, no metadata** beyond the color profile. Run `pngcrush` or `oxipng -o 4` on each to strip extraneous chunks and minimize size.
- **Drop-in placement:** all 10 referenced PNGs go into `Ice/Resources/Assets.xcassets/AppIcon.appiconset/`, overwriting the existing files. `Contents.json` does **not** need to change — filenames already match. The 1024×1024 master goes into the repo at `Resources/icon-master/icon_1024x1024.png` (or similar — outside the .xcassets, since Xcode will warn about unreferenced files).
- **Verification step:** after replacement, run `xcrun actool --compile /tmp/out Ice/Resources/Assets.xcassets --platform macosx --minimum-deployment-target 14.0 --output-partial-info-plist /tmp/info.plist` to confirm Xcode accepts the assets without warnings.

---

**Designer/AI sanity check before delivery:** open the 16×16 next to the existing Ice 16×16 at actual size on a real Retina display. They should read as a clear pair — same canvas geometry, opposite temperature — at a glance.

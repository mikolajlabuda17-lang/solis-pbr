# Solis PBR — Realistic Shader Pack for Horizon (Shader API 0.2)

**Solis PBR** is a physically-based shader pack written from scratch in **WGSL** for **Horizon** (Minecraft: Java Edition 26.3 rewritten in Rust, **Shader API 0.2**, linear HDR pipeline).

## Highlights

- **Physical Atmosphere & Celestial Bodies (`sky.wgsl`, `lib/atmosphere.wgsl`)**:
  - Rayleigh & Mie scattering, Ozone Chappuis sunset absorption, Belt of Venus, HDR Sun with Eddington limb darkening, cratered 3D Moon with basaltic maria, phases & earthshine, rotating 3D starfield, Milky Way and cold-biome Aurora Borealis.
- **Total Solar Eclipse at `5800` (`/time set 5800`)**:
  - Full 20-second Total Solar Eclipse (`5800–6200` ticks, with partial ingress/egress across `5350–6646`), featuring fibrous magnetic coronal streamers, H-alpha solar prominences, Diamond Ring flashes, a 360° copper-amber twilight horizon, daytime zenith stars and silver coronal lighting across the world.
- **3D Volumetric Clouds & Bilateral SSAO (`post/clouds_ssao.wgsl`, `post/composite.wgsl`)**:
  - Raymarched Perlin-Worley cumulus clouds with Beer-Powder multi-scattering, temporal reprojection (`[[resource]]`) and high-altitude cirrus, plus normal-aware SSAO.
- **PBR Materials, LabPBR, Soft PCF & Coloured Shadows (`material.wgsl`, `entity.wgsl`, `lib/lighting.wgsl`)**:
  - Microfacet Cook-Torrance GGX BRDF, Schlick Fresnel, foliage subsurface scattering (SSS), LabPBR (`_n`, `_s`) + geometric relief (`[displacement]`), rotated Vogel-disk PCF shadows, stained-glass & water coloured shadows, multi-colour block/particle lights and glowing mineral ore veins (`Emissive Ores`).
- **Optical Water, Rain Puddles & SSR (`lib/water.wgsl`, `post/composite.wgsl`)**:
  - 4-wave Gerstner normals, depth-guarded refraction, Beer-Lambert spectral absorption, dual-layer Voronoi seabed caustics, shore foam, planar water mirror (`[reflection]`), rain wetness, rippling puddles and Screen-Space Reflections (SSR).
- **Camera, FXAA & HDR/SDR Tonemapping (`post/bloom.wgsl`, `post/grade_fxaa.wgsl`, `tonemap.wgsl`)**:
  - Karis HDR bloom, volumetric 3D shadow-map god rays, subtle optical lens flare, smooth eye adaptation, FXAA and selectable **AgX**, **ACES Fitted** or **Khronos PBR Neutral** display transforms (`frame.headroom` HDR ready).

## GPU Requirements

*No hardware Ray Tracing (RTX) required — runs on Vulkan 1.2 / DirectX 12 / Metal.*

- **Minimum (`1080p ~60 FPS`, 1024 shadows, Fast clouds):** GTX 1050 Ti / RX 560 / Intel Iris Xe / Radeon 680M / Apple M1 / Steam Deck (2 GB+ VRAM)
- **Recommended (`1080p 90+ FPS` / `1440p 60+ FPS`, default High preset):** GTX 1660 Super / RTX 2060 / RX 6600 / Intel Arc A580 / Apple M2+ (4–6 GB VRAM)
- **Ultra / 4K (`4096` shadows):** RTX 3060 Ti / RTX 4060 / RX 6700 XT or higher (8 GB+ VRAM)

## Installation

1. Copy `solis_pbr-1.1.0.hshader` into `shaderpacks/` next to `options.txt`.
2. In Horizon, open **Options > Video Settings > Shaders > Shader Packs...** and select **Solis PBR**.
3. Open **Shader Options...** to customize all 48 settings across 6 categories (including **The End & Black Hole**).

## Build & Check from Source

```sh
horizon-shader check .
horizon-shader pack . --out solis_pbr-1.1.0.hshader
```

## License

MIT — see [LICENSE](LICENSE).

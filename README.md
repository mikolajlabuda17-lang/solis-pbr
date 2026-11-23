# Solis PBR — Realistic Shader Pack for Horizon (Shader API 0.2)

**Solis PBR** is a physically-based shader pack written from scratch in **WGSL** for **Horizon** (Minecraft: Java Edition 26.3 rewritten in Rust, **Shader API 0.2**, linear HDR pipeline).

## Highlights

- **Physical Atmosphere & Celestial Bodies (`sky.wgsl`, `lib/atmosphere.wgsl`)**:
  - Rayleigh & Mie scattering, Ozone Chappuis sunset absorption, Belt of Venus, HDR Sun with Eddington limb darkening, cratered 3D Moon with basaltic maria, phases & earthshine, rotating 3D starfield, Milky Way and cold-biome Aurora Borealis.
- **6 Scheduled Hyper-Realistic Astronomical Spectacles & Atmospheric Optics (`lib/astronomy.wgsl`, `lib/atmosphere.wgsl`)**:
  - **`/time set 1200` — 22° Hexagonal Ice Halo & Sundogs (Parhelia):** Prismatic 22° prism halo, twin dazzling Sundogs, 360° Parhelic Circle, Upper Tangent Arc, and Circumzenithal zenith rainbow.
  - **`/time set 5800` — Total Solar Eclipse:** 20-second totality with fibrous magnetic coronal streamers, H-alpha solar prominences, Diamond Ring flash, 360° twilight horizon, and daytime stars.
  - **`/time set 13200` — Great Comet C/Solis:** Hale-Bopp / NEOWISE-class twin-tailed comet with emerald $C_2$ coma, sweeping curved Mie-scattering golden dust tail with synchrone striations, and straight electric-blue $CO^+$ ion tail.
  - **`/time set 15500` — Galactic Supernova, V838 Light-Echo Nebula & Perseid Meteor Storm:** 18,000K core with chromatic Fraunhofer diffraction spikes, multi-shell interstellar dust light echo, sapphire world starlight, and green-wake (`557.7 nm`) shooting stars.
  - **`/time set 18000` — Total Lunar Eclipse ("Copper Blood Supermoon"):** Perigee 3D cratered Supermoon immersed in Earth's spherical umbra with refracted Rayleigh sunset copper-crimson gradient and Danjon Chappuis-band turquoise ozone fringe.
  - **`/time set 20500` — Extreme G5 Geomagnetic Storm (SAR Red & Corona Aurora):** Multi-altitude geomagnetic curtains converging into a magnetic-zenith corona (`427.8 nm` violet fringe, `557.7 nm` emerald curtain, `630.0 nm` towering scarlet SAR canopy).
  - **Post-Rain 42°/51° Double Rainbow:** Descartes primary + reversed secondary rainbow, Airy supernumerary fringes, and Alexander's Dark Band.
- **The End Overhaul & Relativistic "Gargantua" Black Hole (`lib/end_gargantua.wgsl`)**:
  - Curved-spacetime Schwarzschild geodesic raytracing with pitch-black Event Horizon, razor-sharp Photon Ring, gravitationally lensed upper & lower Keplerian accretion disk arches, relativistic Doppler beaming, Einstein-lensed deep-space starfield, IMAX anamorphic flare, golden crepuscular rays, full water reflections, and GGX directional End island PBR lighting.
- **Volcanic Nether Overhaul & Thermal Mirage (`lib/nether_volcanic.wgsl`)**:
  - Stefan-Boltzmann blackbody lava cooling crust with 1580K convective fissures, biome-adaptive 3D volcanic ash & lava-sea underglow, GGX PBR specular on Basalt/Blackstone/Gold/Quartz, intracloud storm lightning, and convective Heat Shimmer / Mirage.
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

1. Copy `solis_pbr-1.1.5.hshader` into `shaderpacks/` next to `options.txt`.
2. In Horizon, open **Options > Video Settings > Shaders > Shader Packs...** and select **Solis PBR**.
3. Open **Shader Options...** to customize all 59 settings across 8 categories.

## Build & Check from Source

```sh
horizon-shader check .
horizon-shader pack . --out solis_pbr-1.1.5.hshader
```

## License

MIT — see [LICENSE](LICENSE).

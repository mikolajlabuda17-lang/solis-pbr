// ============================================================================
// Solis PBR 1.1.5 — Shared Constants, Options & Astronomical Event Windows
// ============================================================================

const PI: f32 = 3.141592653589793;
const TAU: f32 = 6.283185307179586;
const INV_PI: f32 = 0.3183098861837907;
const GOLDEN_ANGLE: f32 = 2.399963229728653;

// --- Sprite Tag Masks (matching [[tags]] order in horizon-shaders.toml) ---
const TAG_GLASS: u32              = 1u;
const TAG_ICE_SURFACE: u32        = 2u;
const TAG_SUBSURFACE_FOLIAGE: u32 = 4u;
const TAG_UPPER_PLANT_HALF: u32   = 8u;
const TAG_LOWER_PLANT_HALF: u32   = 16u;

// --- Material IDs (matching [[materials]] in horizon-shaders.toml) ---
const MAT_LEAVES: u32       = 10u;
const MAT_SHORT_PLANTS: u32 = 11u;
const MAT_TALL_PLANTS: u32  = 12u;
const MAT_HANGING_VINE: u32 = 13u;
const MAT_AQUATIC: u32      = 14u;
const MAT_METAL: u32        = 20u;
const MAT_POLISHED: u32     = 21u;
const MAT_CRYSTAL: u32      = 22u;
const MAT_GRANULAR: u32     = 23u;
const MAT_ORE: u32          = 30u;
const MAT_BIOLUM: u32       = 31u;

// --- Pack Options (WGSL overrides) ---
override shadows_enabled: bool     = true;
override shadow_softness: f32      = 1.25;
override colored_shadows: bool     = true;
override ssao_enabled: bool        = true;
override ssao_strength: f32        = 0.75;
override block_light_intensity: f32 = 1.15;
override emissive_ores: bool       = true;
override ore_glow_strength: f32    = 1.2;

override solar_eclipse: bool       = true;
override lunar_eclipse: bool       = true;
override ice_halos_enabled: bool   = true;
override great_comet_enabled: bool = true;
override supernova_enabled: bool   = true;
override g5_aurora_storm: bool     = true;
override rainbow_enabled: bool     = true;
override meteors_enabled: bool     = true;

override celestial_size: f32       = 1.0;
override stars_enabled: bool       = true;
override volumetric_clouds: bool   = true;
override cloud_quality: u32        = 2u;
override cloud_coverage: f32       = 0.48;
override cirrus_clouds: bool       = true;
override godrays_enabled: bool     = true;
override godrays_strength: f32     = 0.85;
override fog_density: f32          = 1.0;
override aurora_enabled: bool      = true;

override water_reflections: bool   = true;
override water_wave_height: f32    = 1.0;
override water_clarity: f32        = 1.0;
override caustics_strength: f32    = 1.0;
override shore_foam: bool          = true;
override water_refraction: f32     = 1.0;

override labpbr_enabled: bool      = true;
override pom_displacement: bool    = true;
override specular_strength: f32    = 1.0;
override rain_puddles: bool        = true;
override puddle_coverage: f32      = 0.60;
override wet_ssr: bool             = true;
override wind_enabled: bool        = true;
override wind_strength: f32        = 1.0;

override tonemap_operator: u32     = 0u;
override exposure: f32             = 0.0;
override auto_exposure: f32        = 0.45;
override bloom_enabled: bool       = true;
override bloom_strength: f32       = 0.14;
override sun_flare: bool           = true;
override contrast: f32             = 1.04;
override saturation: f32           = 1.05;
override vibrance: f32             = 0.12;
override vignette_strength: f32    = 0.22;
override fxaa_enabled: bool        = true;

override end_black_hole: bool      = true;
override end_bh_size: f32          = 1.0;
override end_disk_intensity: f32   = 1.15;
override end_doppler_shift: f32    = 1.0;
override end_ambient_light: f32    = 1.0;

override nether_overhaul: bool     = true;
override nether_heat_haze: bool    = true;
override nether_fog_density: f32   = 1.0;
override nether_lava_glow: f32     = 1.25;

// --- Safe Math & Color Helpers ---
fn saturate_f(x: f32) -> f32 {
    return clamp(x, 0.0, 1.0);
}

fn saturate_v3(v: vec3<f32>) -> vec3<f32> {
    return clamp(v, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sqr(x: f32) -> f32 {
    return x * x;
}

fn pow5(x: f32) -> f32 {
    let x2 = x * x;
    return x2 * x2 * x;
}

fn luma(c: vec3<f32>) -> f32 {
    return dot(max(c, vec3<f32>(0.0)), frame.luminance);
}

// Wrapped signed tick distance on the 24000-tick Minecraft cycle
fn wrapped_tick_delta(ticks: f32, center_tick: f32) -> f32 {
    var dt = ticks - center_tick;
    if dt > 12000.0 {
        dt -= 24000.0;
    }
    if dt < -12000.0 {
        dt += 24000.0;
    }
    return dt;
}

// Smooth plateau envelope: 1.0 inside [-plateau_half, +plateau_half], smooth cosine/hermite ramp out to fade_half
fn eval_event_plateau(ticks: f32, center: f32, plateau_half: f32, total_half: f32) -> f32 {
    let adt = abs(wrapped_tick_delta(ticks, center));
    if adt >= total_half {
        return 0.0;
    }
    if adt <= plateau_half {
        return 1.0;
    }
    return smoothstep(total_half, plateau_half, adt);
}

// Fast spatial interleaved gradient noise (Jorge Jimenez) + temporal frame offset
fn interleaved_gradient_noise(pixel: vec2<f32>) -> f32 {
    let f = f32(frame.frame_index & 63u);
    let p = pixel + vec2<f32>(5.588238 * f, 5.588238 * f);
    return fract(52.9829189 * fract(dot(p, vec2<f32>(0.06711056, 0.00583715))));
}

// Spatial-only IGN without frame_index flicker
fn spatial_ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

// ============================================================================
// 1. Total Solar Eclipse State centered at `/time set 5800` (5800..6200 plateau)
// ============================================================================
struct EclipseState {
    in_window: bool,
    offset: vec2<f32>,
    sep: f32,
    obscuration: f32,
    totality: f32,
    diamond_ring: f32,
}

fn eval_solar_eclipse() -> EclipseState {
    if !solar_eclipse || frame.dimension != 0 {
        return EclipseState(false, vec2<f32>(10.0, 0.0), 10.0, 0.0, 0.0, 0.0);
    }

    let ticks = frame.day_time * 24000.0;
    let dt = wrapped_tick_delta(ticks, 5998.0);
    let adt = abs(dt);
    let plateau_half = 202.0; // [5796 .. 6200] -> /time set 5800 stays in 100% totality for 20s!

    if adt >= 660.0 {
        return EclipseState(false, vec2<f32>(10.0, 0.0), 10.0, 0.0, 0.0, 0.0);
    }

    let rm = 1.036;
    let excess = max(adt - plateau_half, 0.0);
    let sep = (excess / 215.0) * 2.05;

    let sgn = select(-1.0, 1.0, dt >= 0.0);
    let transit_dir = vec2<f32>(0.955, 0.296) * sgn;
    let offset = transit_dir * sep;

    var obsc = 0.0;
    if sep <= (rm - 1.0) {
        obsc = 1.0;
    } else if sep < (1.0 + rm) {
        let d2 = sep * sep;
        let rm2 = rm * rm;
        let cos_a = clamp((d2 + 1.0 - rm2) / max(2.0 * sep, 1e-4), -1.0, 1.0);
        let cos_b = clamp((d2 + rm2 - 1.0) / max(2.0 * sep * rm, 1e-4), -1.0, 1.0);
        let a = acos(cos_a);
        let b = acos(cos_b);
        let term = max((-sep + 1.0 + rm) * (sep + 1.0 - rm) * (sep - 1.0 + rm) * (sep + 1.0 + rm), 0.0);
        let lens_area = a + rm2 * b - 0.5 * sqrt(term);
        obsc = saturate_f(lens_area * INV_PI);
    }

    let totality = smoothstep(0.115, 0.032, sep);
    let diamond = smoothstep(0.19, 0.058, sep) * smoothstep(0.020, 0.046, sep);

    return EclipseState(true, offset, sep, obsc, totality, diamond);
}

// ============================================================================
// 2. Total Lunar Eclipse ("Copper Blood Supermoon") at `/time set 18000`
// ============================================================================
struct LunarEclipseState {
    in_window: bool,
    umbra_offset: vec2<f32>, // Center of Earth's shadow in lunar radii (R_umbra = 2.62 * R_moon)
    umbra_radius: f32,
    immersion: f32,          // 0 = uneclipsed, 1 = deep totality
    totality: f32,
}

fn eval_lunar_eclipse() -> LunarEclipseState {
    if !lunar_eclipse || frame.dimension != 0 {
        return LunarEclipseState(false, vec2<f32>(10.0, 0.0), 2.62, 0.0, 0.0);
    }

    let ticks = frame.day_time * 24000.0;
    // Totality holds across [17920 .. 18480] so `/time set 18000` is immediately in deep totality for ~24s!
    let dt = wrapped_tick_delta(ticks, 18200.0);
    let adt = abs(dt);
    if adt >= 920.0 {
        return LunarEclipseState(false, vec2<f32>(10.0, 0.0), 2.62, 0.0, 0.0);
    }

    let r_umbra = 2.62; // Physical Earth umbral radius at lunar distance (~2.6x R_moon)
    let plateau_half = 280.0;
    let excess = max(adt - plateau_half, 0.0);
    // During totality plateau, Earth's umbra stays slightly off-center (~0.52 R_moon) for realistic Danjon asymmetry!
    let sep = 0.52 + (excess / 640.0) * 3.35;
    let sgn = select(-1.0, 1.0, dt >= 0.0);
    let umbra_off = vec2<f32>(0.92, 0.39) * (sep * sgn);

    let immersion = smoothstep(r_umbra + 1.02, r_umbra - 0.85, sep);
    let totality  = smoothstep(r_umbra - 0.72, r_umbra - 1.02, sep);
    return LunarEclipseState(true, umbra_off, r_umbra, immersion, totality);
}

// ============================================================================
// 3. Morning 22° Ice Halo, Sundogs (Parhelia) & Circumzenithal Arc (`/time set 1200`)
// ============================================================================
fn eval_ice_halo_strength() -> f32 {
    if !ice_halos_enabled || frame.dimension != 0 {
        return 0.0;
    }
    let ticks = frame.day_time * 24000.0;
    // Peak spectacle window around `/time set 1200` ([950 .. 1750] plateau, [550 .. 2250] ramp)
    let morning_event = eval_event_plateau(ticks, 1350.0, 400.0, 880.0);
    // Also naturally appears at lower intensity in freezing snowy biomes when sun is low (< 32 deg)!
    let cold_natural = smoothstep(0.25, -0.05, frame.temperature)
                     * smoothstep(0.04, 0.16, frame.sun_direction.y)
                     * smoothstep(0.62, 0.38, frame.sun_direction.y) * 0.65;
    return max(morning_event, cold_natural) * (1.0 - saturate_f(frame.rain * 0.92));
}

// ============================================================================
// 4. Great Comet C/Solis (Twin Dust & Ion Tails) at `/time set 13200`
// ============================================================================
const GREAT_COMET_DIR: vec3<f32> = vec3<f32>(-0.758, 0.342, -0.555);

fn eval_great_comet_strength() -> f32 {
    if !great_comet_enabled || frame.dimension != 0 {
        return 0.0;
    }
    let ticks = frame.day_time * 24000.0;
    // Peak from post-sunset twilight (`13100`) through early night (`14450`) -> `/time set 13200` hits instant peak!
    return eval_event_plateau(ticks, 13775.0, 675.0, 1180.0) * (1.0 - saturate_f(frame.rain * 0.95));
}

// ============================================================================
// 5. Galactic Supernova + V838 Light-Echo Nebula at `/time set 15500`
// ============================================================================
const SUPERNOVA_DIR: vec3<f32> = vec3<f32>(0.485, 0.545, -0.684);

fn eval_supernova_strength() -> f32 {
    if !supernova_enabled || frame.dimension != 0 {
        return 0.0;
    }
    let ticks = frame.day_time * 24000.0;
    // Peak across [15350 .. 16350], ramp [14900 .. 16900] -> `/time set 15500` hits instant peak!
    return eval_event_plateau(ticks, 15850.0, 500.0, 980.0) * (1.0 - saturate_f(frame.rain * 0.95));
}

// ============================================================================
// 6. Extreme G5 Geomagnetic Storm (Global Crimson SAR & Corona Aurora) at `/time set 20500`
// ============================================================================
fn eval_g5_storm_strength() -> f32 {
    if !g5_aurora_storm || frame.dimension != 0 {
        return 0.0;
    }
    let ticks = frame.day_time * 24000.0;
    // Peak across [20300 .. 21300], ramp [19650 .. 22100] -> `/time set 20500` hits instant peak!
    return eval_event_plateau(ticks, 20800.0, 500.0, 1180.0) * (1.0 - saturate_f(frame.rain * 0.90));
}

fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Sample our seamless 128x128 procedural noise texture cleanly with explicit LOD 0
fn sample_noise(uv: vec2<f32>) -> vec4<f32> {
    return textureSampleLevel(noise_tex, noise_tex_sampler, uv, 0.0);
}

// Henyey-Greenstein scattering phase function
fn hg_phase(cos_theta: f32, g: f32) -> f32 {
    let g2 = g * g;
    let denom = max(1.0 + g2 - 2.0 * g * cos_theta, 1e-4);
    return (1.0 - g2) / (4.0 * PI * denom * sqrt(denom));
}

// Dual-lobe Henyey-Greenstein phase for clouds & aerosols
fn dual_hg_phase(cos_theta: f32, g_fwd: f32, g_back: f32, w_fwd: f32) -> f32 {
    return mix(hg_phase(cos_theta, g_back), hg_phase(cos_theta, g_fwd), w_fwd);
}

// Rayleigh molecular scattering phase
fn rayleigh_phase(cos_theta: f32) -> f32 {
    return (3.0 / (16.0 * PI)) * (1.0 + cos_theta * cos_theta);
}

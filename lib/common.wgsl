// ============================================================================
// Solis PBR — Shared Constants, Options & Mathematical Utilities (API 0.2)
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
// Total Solar Eclipse State centered at day_time == 5800 ticks
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

    // Totality holds stationary for 20 full seconds (400 ticks: 5800 .. 6200, with 4-tick lead-in at 5796)
    let ticks = frame.day_time * 24000.0;
    let plateau_center = 5998.0;
    let plateau_half   = 202.0; // [5796 .. 6200] -> /time set 5800 stays in 100% totality for 20s (400 ticks)!

    var dt = ticks - plateau_center;
    if dt > 12000.0 {
        dt -= 24000.0;
    }
    if dt < -12000.0 {
        dt += 24000.0;
    }

    let adt = abs(dt);
    // Full ingress + 20s totality + egress window: 5338 .. 6658 ticks
    if adt >= 660.0 {
        return EclipseState(false, vec2<f32>(10.0, 0.0), 10.0, 0.0, 0.0, 0.0);
    }

    // Moon apparent radius = 1.036 * Sun radius; sep == 0.0 throughout the entire 20-second plateau
    let rm = 1.036;
    let excess = max(adt - plateau_half, 0.0);
    let sep = (excess / 215.0) * 2.05;

    let sgn = select(-1.0, 1.0, dt >= 0.0);
    let transit_dir = vec2<f32>(0.955, 0.296) * sgn;
    let offset = transit_dir * sep;

    // Exact circle-circle overlap fraction of the solar disc (R_sun = 1.0, R_moon = rm)
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

// Dual-lobe Henyey-Greenstein phase for clouds & aerosols (forward silver-lining + backscatter)
fn dual_hg_phase(cos_theta: f32, g_fwd: f32, g_back: f32, w_fwd: f32) -> f32 {
    return mix(hg_phase(cos_theta, g_back), hg_phase(cos_theta, g_fwd), w_fwd);
}

// Rayleigh molecular scattering phase
fn rayleigh_phase(cos_theta: f32) -> f32 {
    return (3.0 / (16.0 * PI)) * (1.0 + cos_theta * cos_theta);
}

// ============================================================================
// Solis PBR 1.1.5 — Hyper-Realistic Volcanic Nether Sky, Lava & Fog (`dimension == -1`)
// ============================================================================

// Normalize biome fog tint into a rich, non-muddy chromatic signature per Nether biome
fn get_nether_biome_palette() -> vec3<f32> {
    let fc = max(frame.fog_color, vec3<f32>(0.005));
    let lum = max(luma(fc), 0.012);
    let chroma = clamp(fc / lum, vec3<f32>(0.25), vec3<f32>(2.6));
    return mix(vec3<f32>(0.78, 0.28, 0.12), chroma * 0.55, 0.78);
}

// Smooth 3-octave rotated Perlin FBM using `.r` channel (zero Voronoi cellular artifacts!)
fn nether_fbm(p: vec2<f32>) -> f32 {
    let n1 = sample_noise(p).r;
    let p2 = vec2<f32>(p.x * 1.62 - p.y * 1.24, p.x * 1.24 + p.y * 1.62) + vec2<f32>(0.37, 0.71);
    let n2 = sample_noise(p2).r;
    let p3 = vec2<f32>(p2.x * 1.75 + p2.y * 1.18, -p2.x * 1.18 + p2.y * 1.75) + vec2<f32>(0.19, 0.53);
    let n3 = sample_noise(p3).r;
    return n1 * 0.55 + n2 * 0.30 + n3 * 0.15;
}

// Physically-motivated Stefan-Boltzmann Blackbody Lava with Cooling Basaltic Pahoehoe Crust & Incandescent Fissures!
fn eval_volcanic_lava_hdr(base_albedo: vec3<f32>, world_pos: vec3<f32>, geom_normal: vec3<f32>) -> vec3<f32> {
    let tex_heat = luma(base_albedo);
    let is_flat = abs(geom_normal.y) > 0.65;
    let t = frame.time * 0.014;

    var crust_factor = 0.0;
    var fissure_glow = 0.0;
    if is_flat {
        let warp = vec2<f32>(
            sample_noise(world_pos.xz * 0.032 + vec2<f32>(t, -t * 0.7)).r,
            sample_noise(world_pos.xz * 0.032 + vec2<f32>(0.43 - t * 0.6, 0.29 + t)).r
        ) - vec2<f32>(0.5);
        let fbm_val = nether_fbm(world_pos.xz * 0.068 + warp * 0.38 + vec2<f32>(t * 0.8, t * 0.45));
        // Dark cooled basaltic slag islands with incandescent white-orange magma cracks along boundaries!
        crust_factor = smoothstep(0.50, 0.72, fbm_val - (tex_heat - 0.38) * 0.55);
        fissure_glow = exp(-sqr((fbm_val - 0.49) / 0.045)) * 1.35;
    }

    let hot_core = pow(max(tex_heat, 0.0), 2.05);
    let slag_col = vec3<f32>(0.075, 0.018, 0.008);
    let molten_col = base_albedo * (1.95 + hot_core * 4.6)
                   + vec3<f32>(1.15, 0.86, 0.44) * (pow(hot_core, 2.1) * 1.65 + fissure_glow);
    let glow_scale = select(1.0, nether_lava_glow, frame.dimension == -1);
    return mix(molten_col, slag_col, crust_factor * 0.84) * glow_scale;
}

// 3D Volumetric Nether Sky / Far Cavern Background (`d == 0.0` in Nether)
fn eval_nether_sky(ray_dir: vec3<f32>) -> vec3<f32> {
    if !nether_overhaul {
        return frame.fog_color;
    }
    let d = normalize(ray_dir);
    let pal = get_nether_biome_palette();

    let down_glow = smoothstep(0.28, -0.55, d.y);
    let horizon_band = exp(-abs(d.y + 0.04) * 4.2);

    let plume_uv = vec2<f32>(d.x + d.z * 0.65, d.y * 1.4 - frame.time * 0.018) * 0.75;
    let n_smoke = nether_fbm(plume_uv);

    let ceiling_col = pal * 0.032 * (0.60 + 0.80 * n_smoke);
    let horizon_col = pal * 0.14 * (0.72 + 0.56 * n_smoke) + vec3<f32>(0.34, 0.095, 0.022) * horizon_band * nether_lava_glow;
    let abyss_lava  = vec3<f32>(0.56, 0.14, 0.025) * down_glow * nether_lava_glow;

    return max(mix(ceiling_col, horizon_col, smoothstep(0.65, -0.05, d.y)) + abyss_lava * 0.42, vec3<f32>(0.0));
}

// Biome-Adaptive Volumetric Nether Ash, Spore & Lava-Sea Underglow Fog
// Bypasses vanilla's ultra-short Nether `v_fog` wall so caverns, fortresses & lava seas stay crystal-crisp!
fn apply_nether_volumetric_fog(surface_color: vec3<f32>, camera_rel_pos: vec3<f32>) -> vec3<f32> {
    if !nether_overhaul {
        return mix(surface_color, frame.fog_color, vanilla_fog(camera_rel_pos));
    }

    let dist = length(camera_rel_pos);
    let view_dir = camera_rel_pos / max(dist, 1e-4);
    let world_pos = frame.camera_position + camera_rel_pos;

    let lava_sea_prox = smoothstep(54.0, 28.0, world_pos.y);
    let sigma = (0.0034 + lava_sea_prox * 0.0042) * nether_fog_density;
    let vol_t = 1.0 - exp(-dist * sigma);
    let far_fade = smoothstep(0.68, 1.0, dist / max(frame.far, 48.0));

    let smoke_uv = world_pos.xz * 0.010 + vec2<f32>(frame.time * 0.009, -frame.time * 0.006);
    let smoke_var = 0.82 + 0.36 * sample_noise(smoke_uv).r;

    let base_medium = eval_nether_sky(view_dir) * smoke_var;
    let lava_bounce = vec3<f32>(0.68, 0.19, 0.035) * lava_sea_prox * nether_lava_glow * 0.24;
    let fog_rgb = base_medium + lava_bounce;

    let combined_t = saturate_f(max(vol_t * 0.78, far_fade * 0.94));
    return mix(surface_color, fog_rgb, combined_t);
}

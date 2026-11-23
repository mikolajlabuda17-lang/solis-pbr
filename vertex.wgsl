// ============================================================================
// Solis PBR — Vertex Stage (`[vertex]`): Foliage Wind, Kelp Current & Waves
// ============================================================================

fn vertex(input: VertexInput) -> vec3<f32> {
    let dist_sq = dot(input.position, input.position);
    // Fade vertex motion smoothly beyond 72 blocks to save vertex work & prevent distant shimmer
    let lod_fade = 1.0 - smoothstep(3600.0, 5400.0, dist_sq);
    if lod_fade <= 0.001 {
        return input.position;
    }

    let world_pos = input.position + frame.camera_position;

    // 1. Subtle Gerstner surface bob on still water tops (water top sits ~0.88 in block)
    if input.fluid == 1u && water_wave_height > 0.01 {
        let frac_y = fract(world_pos.y);
        if frac_y > 0.72 && frac_y < 0.96 {
            let t = frame.time;
            let w1 = sin(world_pos.x * 1.45 + world_pos.z * 0.85 + t * 1.65);
            let w2 = cos(world_pos.x * 0.75 - world_pos.z * 2.15 + t * 2.20);
            let dy = (w1 * 0.026 + w2 * 0.016) * water_wave_height * lod_fade;
            return input.position + vec3<f32>(0.0, dy, 0.0);
        }
        return input.position;
    }

    if !wind_enabled {
        return input.position;
    }

    let mat = input.material;
    if mat < MAT_LEAVES || mat > MAT_AQUATIC {
        return input.position;
    }

    // Outdoor exposure scales wind by sky light so indoor flowerpots stay calm!
    let sky_expose = smoothstep(0.10, 0.75, input.light.y);
    let weather_gust = 1.0 + frame.rain * 0.65 + frame.thunder * 0.85;
    let t = frame.time * (1.55 + frame.rain * 0.65 + frame.thunder * 0.55);
    let phase = world_pos.x * 0.75 + world_pos.z * 0.55 + world_pos.y * 0.45;

    // 2. Tree Leaves: continuous 3D world-space rustle (zero block-seam cracking)
    if mat == MAT_LEAVES {
        let amp = 0.036 * wind_strength * weather_gust * (0.25 + 0.75 * sky_expose) * lod_fade;
        let sx = sin(t * 1.35 + phase) + 0.45 * sin(t * 2.75 + world_pos.y * 2.1);
        let sz = cos(t * 1.15 + phase * 1.15) + 0.45 * cos(t * 2.45 + world_pos.x * 1.9);
        let sy = sin(t * 1.85 + phase * 0.8) * 0.35;
        return input.position + vec3<f32>(sx, sy, sz) * amp;
    }

    // 3. Grounded Short Grass, Flowers & Crops: pinned at root (uv.y == 1.0)
    if mat == MAT_SHORT_PLANTS {
        let tip_weight = saturate_f(1.0 - input.uv.y);
        let amp = 0.068 * wind_strength * weather_gust * sky_expose * tip_weight * tip_weight * lod_fade;
        let gust = 0.75 + 0.25 * sin(t * 0.45 - world_pos.x * 0.12 - world_pos.z * 0.08);
        let sx = sin(t * 1.65 + phase) * gust;
        let sz = cos(t * 1.35 + phase * 0.92) * gust * 0.75;
        return input.position + vec3<f32>(sx, -abs(sx) * 0.12, sz) * amp;
    }

    // 4. Two-Block Tall Plants & Hanging Vines: gentle continuous sway
    if mat == MAT_TALL_PLANTS || mat == MAT_HANGING_VINE {
        let amp = 0.042 * wind_strength * weather_gust * (0.2 + 0.8 * sky_expose) * lod_fade;
        let sx = sin(t * 1.25 + phase + world_pos.y * 0.65);
        let sz = cos(t * 1.05 + phase * 0.88 + world_pos.y * 0.65) * 0.85;
        return input.position + vec3<f32>(sx, 0.0, sz) * amp;
    }

    // 5. Underwater Seagrass & Kelp: smooth rolling ocean current
    if mat == MAT_AQUATIC {
        let ct = frame.time * 1.15;
        let c_phase = world_pos.x * 0.55 + world_pos.z * 0.55 - world_pos.y * 0.85;
        let amp = 0.055 * wind_strength * lod_fade;
        let sx = sin(ct + c_phase);
        let sz = cos(ct * 0.82 + c_phase * 1.12);
        return input.position + vec3<f32>(sx, 0.0, sz) * amp;
    }

    return input.position;
}

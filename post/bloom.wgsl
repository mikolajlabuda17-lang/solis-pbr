// ============================================================================
// Solis PBR — Post Pass 4 (`bloom_quarter`, 0.25x): Soft-Knee Karis HDR Bloom
// ============================================================================

fn soft_bright_pass(c: vec3<f32>) -> vec3<f32> {
    let clean = max(c, vec3<f32>(0.0));
    let br = max(clean.r, max(clean.g, clean.b));
    if br <= 1e-5 {
        return vec3<f32>(0.0);
    }
    let threshold = 0.88;
    let knee = 0.52;
    let soft = clamp(br - threshold + knee, 0.0, 2.0 * knee);
    let contrib = (soft * soft) / (4.0 * knee + 1e-5);
    let factor = max(contrib, br - threshold) / br;
    // Karis weighting suppresses single-pixel specular fireflies
    let karis = 1.0 / (1.0 + luma(clean) * 0.18);
    return clean * factor * karis;
}

fn post(input: PostInput) -> vec4<f32> {
    if !bloom_enabled || bloom_strength <= 0.005 {
        return vec4<f32>(0.0);
    }

    let texel = 2.5 / max(frame.resolution, vec2<f32>(1.0));
    let uv = input.uv;

    // 13-tap Jimenez dual-ring filter across `previous` (composite HDR output)
    var accum = soft_bright_pass(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb) * 0.22;

    // Inner ring (4 taps)
    for (var i = 0u; i < 4u; i++) {
        let ang = f32(i) * (TAU * 0.25) + 0.392699;
        let off = vec2<f32>(cos(ang), sin(ang)) * texel * 1.45;
        accum += soft_bright_pass(textureSampleLevel(previous, linear_sampler, uv + off, 0.0).rgb) * 0.11;
    }

    // Outer ring (8 taps)
    for (var j = 0u; j < 8u; j++) {
        let ang = f32(j) * (TAU * 0.125);
        let off = vec2<f32>(cos(ang), sin(ang)) * texel * 3.40;
        accum += soft_bright_pass(textureSampleLevel(previous, linear_sampler, uv + off, 0.0).rgb) * 0.0425;
    }

    return vec4<f32>(accum, 1.0);
}

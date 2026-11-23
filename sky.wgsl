// ============================================================================
// Solis PBR — Sky Stage (`[sky]`)
// ============================================================================

fn sky(input: SkyInput) -> vec4<f32> {
    let dir = normalize(input.direction);
    let sky_rgb = eval_physical_sky(dir, true);
    return vec4<f32>(sky_rgb, 1.0);
}

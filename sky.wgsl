// ============================================================================
// Solis PBR — Sky Stage (`[sky]`)
// ============================================================================

fn sky(input: SkyInput) -> vec4<f32> {
    // The End (`1`) and Nether (`-1`) composite their full-precision 3D sky in `post/composite.wgsl` (`d == 0.0`).
    // Returning black here prevents `[sky]` from ever drawing a duplicate sky/black-hole into `scene_color`!
    if frame.dimension == 1 || frame.dimension == -1 {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    let dir = normalize(input.direction);
    let sky_rgb = eval_physical_sky(dir, true);
    return vec4<f32>(sky_rgb, 1.0);
}

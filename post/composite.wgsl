// ============================================================================
// Solis PBR — Post Pass 3 (Full-Res Chain): Clouds, Bilateral SSAO, SSR & Shafts
// ============================================================================

// Depth- & sentinel-guarded 3x3 tent upsample for volumetric sky clouds (silky smooth half-res -> 1x)
fn upsample_sky_clouds(uv: vec2<f32>) -> vec4<f32> {
    let dims_i = vec2<i32>(textureDimensions(atmo_half));
    let dims_f = vec2<f32>(dims_i);
    let coord = uv * dims_f - vec2<f32>(0.5);
    let center = vec2<i32>(round(coord));

    var sum = vec4<f32>(0.0);
    var w_sum = 0.0;

    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            let tc = clamp(center + vec2<i32>(dx, dy), vec2<i32>(0), dims_i - vec2<i32>(1));
            let val = textureLoad(atmo_half, tc, 0);
            if val.r >= 0.0 {
                let sample_center = vec2<f32>(tc);
                let dist2 = dot(coord - sample_center, coord - sample_center);
                let w = exp(-dist2 * 1.15);
                sum += val * w;
                w_sum += w;
            }
        }
    }

    if w_sum <= 1e-4 {
        return vec4<f32>(0.0);
    }
    return sum / w_sum;
}

// Depth-aware 2x2 bilateral upsample for SSAO on geometry (`depth > 0.0`)
fn upsample_ssao_bilateral(uv: vec2<f32>, center_depth: f32) -> f32 {
    let dims_i = vec2<i32>(textureDimensions(atmo_half));
    let dims_f = vec2<f32>(dims_i);
    let coord = uv * dims_f - vec2<f32>(0.5);
    let base = vec2<i32>(floor(coord));
    let f = fract(coord);

    var ao_sum = 0.0;
    var w_sum = 0.0;

    for (var dy = 0; dy <= 1; dy++) {
        for (var dx = 0; dx <= 1; dx++) {
            let tc = clamp(base + vec2<i32>(dx, dy), vec2<i32>(0), dims_i - vec2<i32>(1));
            let val = textureLoad(atmo_half, tc, 0);
            if val.r < -0.25 {
                let suv = (vec2<f32>(tc) + vec2<f32>(0.5)) / dims_f;
                let sd = depth_at(suv);
                let wx = select(1.0 - f.x, f.x, dx == 1);
                let wy = select(1.0 - f.y, f.y, dy == 1);
                let w_depth = exp(-abs(sd - center_depth) * 240.0);
                let w = wx * wy * w_depth;
                ao_sum += val.a * w;
                w_sum += w;
            }
        }
    }

    if w_sum <= 1e-4 {
        return 1.0;
    }
    return ao_sum / w_sum;
}

// Screen-Space Reflections (SSR) for rain puddles and smooth polished/metallic blocks
fn trace_wet_ssr(uv: vec2<f32>, rev_depth: f32, pixel: vec2<f32>, normal: vec3<f32>, smoothness: f32, weight: f32) -> vec4<f32> {
    let origin = view_position(uv, rev_depth);
    let dist = length(origin);
    if dist > 64.0 || dist < 0.25 {
        return vec4<f32>(0.0);
    }

    let view_dir = -origin / dist;
    let refl_dir = reflect(-view_dir, normal);
    let n_dot_v = saturate_f(dot(normal, view_dir));
    let fresnel = 0.03 + 0.97 * pow5(1.0 - n_dot_v);

    let jitter = interleaved_gradient_noise(pixel);
    let view_proj = frame.projection * frame.view;

    var hit_uv = vec2<f32>(0.0);
    var hit_found = false;

    var t = 0.18 + jitter * 0.14;
    for (var i = 0u; i < 12u; i++) {
        let p = origin + refl_dir * t;
        let clip = view_proj * vec4<f32>(p, 1.0);
        if clip.w <= 0.05 {
            break;
        }
        let ndc = clip.xy / clip.w;
        let ray_rev_z = clip.z / clip.w;
        let suv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);

        if suv.x < 0.002 || suv.x > 0.998 || suv.y < 0.002 || suv.y > 0.998 || ray_rev_z <= 0.0 || ray_rev_z >= 1.0 {
            break;
        }

        let scene_rev_z = depth_at(suv);
        if scene_rev_z > ray_rev_z {
            let hit_pos = view_position(suv, scene_rev_z);
            let thickness = length(hit_pos - p);
            if thickness < max(0.65, t * 0.28) {
                hit_uv = suv;
                hit_found = true;
                break;
            }
        }
        t = t * 1.34 + 0.22;
    }

    if !hit_found {
        return vec4<f32>(0.0);
    }

    let edge_fade = smoothstep(0.0, 0.08, hit_uv.x) * smoothstep(1.0, 0.92, hit_uv.x)
                  * smoothstep(0.0, 0.08, hit_uv.y) * smoothstep(1.0, 0.92, hit_uv.y);
    let dist_fade = 1.0 - smoothstep(38.0, 64.0, dist);
    let refl_rgb = textureSampleLevel(scene_color, linear_sampler, hit_uv, 0.0).rgb;
    let refl_alpha = saturate_f(fresnel * weight * smoothness * edge_fade * dist_fade * 0.88);

    return vec4<f32>(refl_rgb, refl_alpha);
}

fn sample_shafts_smooth(uv: vec2<f32>) -> vec3<f32> {
    if !godrays_enabled || godrays_strength <= 0.01 {
        return vec3<f32>(0.0);
    }
    let texel = 4.0 / max(frame.resolution, vec2<f32>(1.0));
    let c0 = textureSampleLevel(shafts_quarter, linear_sampler, uv, 0.0).rgb * 0.40;
    let c1 = textureSampleLevel(shafts_quarter, linear_sampler, uv + vec2<f32>( texel.x,  texel.y), 0.0).rgb * 0.15;
    let c2 = textureSampleLevel(shafts_quarter, linear_sampler, uv + vec2<f32>(-texel.x,  texel.y), 0.0).rgb * 0.15;
    let c3 = textureSampleLevel(shafts_quarter, linear_sampler, uv + vec2<f32>( texel.x, -texel.y), 0.0).rgb * 0.15;
    let c4 = textureSampleLevel(shafts_quarter, linear_sampler, uv + vec2<f32>(-texel.x, -texel.y), 0.0).rgb * 0.15;
    return c0 + c1 + c2 + c3 + c4;
}

// Convective Thermal Mirage / Heat-Shimmer UV Offset (Nether & scorching midday deserts)
fn eval_heat_shimmer_uv(uv: vec2<f32>, rev_depth: f32) -> vec2<f32> {
    if !nether_heat_haze {
        return uv;
    }

    var heat_env = 0.0;
    if frame.dimension == -1 && nether_overhaul {
        heat_env = 1.0;
    } else if frame.dimension == 0 && frame.rain < 0.05 && frame.eye_in == 0u {
        let desert_noon = smoothstep(1.25, 1.85, frame.temperature)
                        * smoothstep(0.45, 0.82, frame.sun_direction.y)
                        * smoothstep(0.45, 0.88, frame.eye_light_smooth.y);
        heat_env = desert_noon * 0.65;
    }

    if heat_env <= 0.01 {
        return uv;
    }

    let dist = select(96.0, length(view_position(uv, rev_depth)), rev_depth > 0.0);
    let dist_ramp = smoothstep(14.0, 68.0, dist);
    if dist_ramp <= 0.01 {
        return uv;
    }

    let t = frame.time;
    let w1 = sample_noise(vec2<f32>(uv.x * 5.5, uv.y * 3.2 - t * 0.22)).rg - vec2<f32>(0.5);
    let w2 = sample_noise(vec2<f32>(uv.x * 11.0 + 0.37, uv.y * 6.8 - t * 0.38)).rg - vec2<f32>(0.5);
    let edge_guard = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x)
                   * smoothstep(0.0, 0.04, uv.y) * smoothstep(1.0, 0.96, uv.y);

    let offset = (w1 * 0.65 + w2 * 0.35) * 0.0024 * heat_env * dist_ramp * edge_guard;
    let cand_uv = clamp(uv + offset, vec2<f32>(0.001), vec2<f32>(0.999));

    let cand_d = depth_at(cand_uv);
    let cand_dist = select(96.0, length(view_position(cand_uv, cand_d)), cand_d > 0.0);
    return select(uv, cand_uv, cand_dist > 10.0);
}

fn post(input: PostInput) -> vec4<f32> {
    let raw_d = input.depth;
    // Apply subtle convective thermal mirage / heat shimmer on distant Nether & scorching desert air!
    let sample_uv = eval_heat_shimmer_uv(input.uv, raw_d);
    let d = select(depth_at(sample_uv), raw_d, all(sample_uv == input.uv));
    var color = select(
        textureSampleLevel(scene_color, linear_sampler, sample_uv, 0.0).rgb,
        input.color.rgb,
        all(sample_uv == input.uv)
    );

    if d == 0.0 {
        if frame.dimension == 1 {
            let p_near = view_position(sample_uv, 0.5);
            let p_far  = view_position(sample_uv, 0.01);
            let ray_dir = normalize(p_far - p_near);
            let beam_excess = max(color - vec3<f32>(0.09), vec3<f32>(0.0));
            color = eval_end_sky(ray_dir, true) + beam_excess;
        } else if frame.dimension == -1 && nether_overhaul {
            let p_near_n = view_position(sample_uv, 0.5);
            let p_far_n  = view_position(sample_uv, 0.01);
            let ray_dir_n = normalize(p_far_n - p_near_n);
            color = eval_nether_sky(ray_dir_n);
        } else {
            // Composite 3D volumetric clouds onto the full-res sky dome (occluding sun, moon & stars smoothly)
            let clouds = upsample_sky_clouds(sample_uv);
            let cloud_a = saturate_f(clouds.a);
            color = color * (1.0 - cloud_a) + max(clouds.rgb, vec3<f32>(0.0));
        }
    } else {
        // Apply bilateral contact-shadow SSAO
        let ao = clamp(upsample_ssao_bilateral(input.uv, d), 0.18, 1.0);
        color *= ao;

        // Screen-Space Reflections on wet puddles & smooth blocks
        if wet_ssr {
            let px = clamp(vec2<i32>(input.uv * frame.resolution), vec2<i32>(0), vec2<i32>(frame.resolution) - vec2<i32>(1));
            let surf = surface_at(px);
            if surf.present && surf.data > 0.04 {
                let ssr = trace_wet_ssr(input.uv, d, input.pixel, surf.normal, surf.smoothness, surf.data);
                color = mix(color, ssr.rgb, ssr.a);
            }
        }
    }

    // Add volumetric crepuscular light shafts (sunbeams, moonbeams & underwater caustic shafts)
    color += sample_shafts_smooth(input.uv);

    return vec4<f32>(max(color, vec3<f32>(0.0)), 1.0);
}

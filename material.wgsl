// ============================================================================
// Solis PBR — Material & Displacement Stage (`[material]`, `[displacement]`)
// ============================================================================

fn displacement(input: DisplacementInput) -> f32 {
    if !labpbr_enabled || !pom_displacement {
        return 0.0;
    }
    // Depth below the flat block face in blocks (0 at height=1, deeper where height<1)
    return (1.0 - saturate_f(input.height)) * 0.075;
}

fn material(input: MaterialInput) -> Surface {
    // 1. Sample LabPBR maps in uniform control flow
    let has_pbr = labpbr_enabled && block_pbr_maps();
    let pbr_n = block_normal_map(input.uv);
    let pbr_s = block_specular_map(input.uv);

    // 2. Water fluid uses dedicated optical refraction, Beer-Lambert & reflection pipeline
    if input.fluid == 1u {
        let water_rgba = shade_water_surface(
            input.position,
            input.normal,
            input.screen,
            input.tint.rgb,
            input.light.y,
            input.light.x,
            input.lightmap,
            input.colored_light
        );
        return Surface(water_rgba);
    }

    let world_pos = input.position + frame.camera_position;
    let dist = length(input.position);
    let view_dir = -input.position / max(dist, 1e-4);
    let mat = input.material;
    let tags = input.tags;

    var base_albedo = input.albedo.rgb * input.tint.rgb;

    // 3. Molten Lava: blackbody HDR emission with hotter bright cracks
    if input.fluid == 2u {
        let heat = luma(base_albedo);
        let lava_hdr = base_albedo * (1.65 + pow(max(heat, 0.0), 1.8) * 3.2);
        let fogged_lava = apply_aerial_fog(lava_hdr, input.position);
        set_surface(input.normal, 0.15, 0.0);
        return Surface(vec4<f32>(fogged_lava, 1.0));
    }

    // 4. Surface Normal, Smoothness, Metallic, F0, Subsurface & AO
    var world_n = input.normal;
    var smoothness = 0.14;
    var metallic = 0.0;
    var subsurface = 0.0;
    var porosity = 0.35;
    var pbr_emissive = 0.0;
    var ao = clamp(input.ao, 0.08, 1.0);

    let is_foliage = (mat >= MAT_LEAVES && mat <= MAT_AQUATIC) || ((tags & TAG_SUBSURFACE_FOLIAGE) != 0u);
    let is_glass_or_ice = ((tags & (TAG_GLASS | TAG_ICE_SURFACE)) != 0u);

    if has_pbr {
        // Decode LabPBR normal (rg = tangent XY, b = texture AO, a = height)
        let n_xy = pbr_n.rg * 2.0 - vec2<f32>(1.0);
        let n_z = sqrt(max(1.0 - dot(n_xy, n_xy), 0.0));
        let t_axis = input.tangent.xyz;
        let b_axis = cross(input.normal, t_axis) * input.tangent.w;
        world_n = normalize(t_axis * n_xy.x + b_axis * n_xy.y + input.normal * n_z);
        ao *= mix(1.0, saturate_f(pbr_n.b), 0.75);

        smoothness = pbr_s.r;
        if pbr_s.g >= (229.5 / 255.0) {
            metallic = 1.0;
        }
        if pbr_s.b <= (64.0 / 255.0) {
            porosity = pbr_s.b * (255.0 / 64.0);
        } else {
            subsurface = (pbr_s.b - (65.0 / 255.0)) * (255.0 / 190.0);
            porosity = 0.1;
        }
        if pbr_s.a > 0.004 && pbr_s.a < 0.996 {
            pbr_emissive = pbr_s.a;
        }
    } else {
        // Procedural PBR material classes when playing with vanilla or non-PBR textures
        let tex_lum = luma(input.albedo.rgb);
        let micro_var = clamp((tex_lum - 0.25) * 0.25, -0.06, 0.12);
        smoothness = clamp(0.14 + micro_var, 0.05, 0.32);

        if mat == MAT_METAL {
            smoothness = clamp(0.70 + micro_var * 0.8, 0.48, 0.88);
            metallic = 0.86;
            porosity = 0.02;
        } else if mat == MAT_POLISHED {
            smoothness = clamp(0.66 + micro_var * 0.6, 0.45, 0.82);
            porosity = 0.08;
        } else if mat == MAT_CRYSTAL || is_glass_or_ice {
            smoothness = 0.86;
            porosity = 0.02;
            subsurface = 0.22;
        } else if is_foliage {
            smoothness = 0.28;
            subsurface = 0.68;
            porosity = 0.18;
        } else if mat == MAT_GRANULAR {
            smoothness = 0.22;
            subsurface = 0.30;
            porosity = 0.65;
        }
    }

    var f0 = select(vec3<f32>(0.04), base_albedo, metallic > 0.5);
    if has_pbr && metallic <= 0.5 && pbr_s.g > 0.004 {
        f0 = vec3<f32>(max(pbr_s.g, 0.02));
    } else if mat == MAT_CRYSTAL || is_glass_or_ice {
        f0 = vec3<f32>(0.055);
    }

    // 5. Rain Wetness, Porous Darkening & Standing Puddles
    var puddle_amount = 0.0;
    if rain_puddles && frame.wetness > 0.005 && frame.dimension == 0 && frame.precipitation == 1u && !input.translucent {
        // Only sky-exposed outdoor blocks get wet
        let sky_open = smoothstep(0.66, 0.93, input.light.y);
        let upward = smoothstep(0.15, 0.95, input.normal.y);
        let wet = frame.wetness * sky_open * (0.35 + 0.65 * upward);

        if wet > 0.01 {
            // Wet porous surfaces darken due to internal total reflection in water film
            let darken = 1.0 - wet * porosity * 0.38 * (1.0 - metallic);
            base_albedo *= darken;
            smoothness = max(smoothness, wet * 0.64);

            // Standing water puddles on flat upward blocks
            if input.normal.y > 0.88 && !is_foliage {
                let pn1 = sample_noise(world_pos.xz * 0.055);
                let pn2 = sample_noise(world_pos.xz * 0.17 + vec2<f32>(0.37, 0.61));
                let puddle_field = pn1.r * 0.68 + pn2.g * 0.32;
                let thresh = 1.0 - puddle_coverage * 0.78;
                puddle_amount = smoothstep(thresh - 0.10, thresh + 0.14, puddle_field) * wet;

                if puddle_amount > 0.01 {
                    let ripples = eval_rain_ripples(world_pos.xz, frame.rain * puddle_amount);
                    let puddle_n = normalize(vec3<f32>(-ripples.x, 1.0, -ripples.y));
                    world_n = normalize(mix(world_n, puddle_n, puddle_amount * 0.90));
                    smoothness = mix(smoothness, 0.94, puddle_amount);
                    f0 = mix(f0, vec3<f32>(0.025), puddle_amount * (1.0 - metallic));
                    base_albedo = mix(base_albedo, base_albedo * 0.78, puddle_amount * 0.65);
                }
            }
        }
    }

    let roughness = max(sqr(1.0 - saturate_f(smoothness)), 0.03);

    // 6. Direct Sun / Moon Illumination + Soft PCF Shadows + Subsurface Scattering
    var total_light = vec3<f32>(0.0);

    if frame.dimension == 0 {
        let env = eval_environment();
        let sky_vis = smoothstep(0.02, 0.95, input.light.y);
        let foliage_relax = select(0.0, 1.0, is_foliage);
        let shadow = eval_sun_shadow(input.position, input.normal, input.screen, foliage_relax);

        let n_dot_l = max(dot(world_n, frame.light_direction), 0.0);
        // Cross-model plants (short grass, flowers) have two-sided quads; soften normal dependence
        let diffuse_nl = select(n_dot_l, mix(n_dot_l, 0.65, 0.55), mat == MAT_SHORT_PLANTS || mat == MAT_TALL_PLANTS);

        // Energy-conserving diffuse + Thin-Foliage Subsurface Transmission
        let kd = (vec3<f32>(1.0) - f0) * (1.0 - metallic);
        var direct_diff = kd * base_albedo * INV_PI * diffuse_nl;

        if subsurface > 0.01 {
            let back_cos = saturate_f(dot(view_dir, -frame.light_direction));
            let wrap_nl = saturate_f((dot(world_n, frame.light_direction) + 0.45) / 1.45);
            let sss_phase = 0.35 + 0.65 * pow(back_cos, 3.0);
            let sss_tint = base_albedo * base_albedo * 1.35 + base_albedo * 0.25;
            direct_diff += sss_tint * INV_PI * subsurface * wrap_nl * sss_phase * 0.85;
        }

        let spec = eval_ggx_specular(world_n, view_dir, frame.light_direction, roughness, f0);
        var sun_contrib = (direct_diff * PI + spec) * env.active_radiance * shadow * saturate_f(sky_vis * 1.15);

        // Underwater caustics when the player is submerged looking at solid terrain
        if frame.eye_in == 1u && !input.translucent {
            let sub_depth = max(63.0 - world_pos.y, 1.5);
            let caust = eval_underwater_caustics(world_pos, frame.light_direction, sub_depth);
            sun_contrib += base_albedo * caust * env.active_radiance * shadow * sky_vis * 0.55;
        }

        // Snow & sand micro-crystal sparkle in direct sunlight
        if mat == MAT_GRANULAR && n_dot_l > 0.1 && smoothness < 0.5 {
            let grain = hash31(floor(world_pos * 24.0));
            let glint_align = saturate_f(dot(normalize(view_dir + frame.light_direction), world_n));
            if grain > 0.965 {
                sun_contrib += env.active_radiance * shadow * pow(glint_align, 18.0) * 0.85;
            }
        }

        // Hemispheric Physical Sky Ambient (cool zenith on top, warm bounce from below)
        let hemi_up = world_n.y * 0.5 + 0.5;
        let sky_hemi = mix(env.sky_horizon * 0.42, env.sky_zenith * 1.28 + env.sky_horizon * 0.45, hemi_up);
        let min_night_amb = vec3<f32>(0.032, 0.048, 0.086) * (1.0 + frame.brightness * 0.65 + frame.night_vision * 6.5);
        let canopy_sky = mix(sky_vis, sky_vis * sky_vis, 0.45);
        let sky_ambient = max(sky_hemi, min_night_amb) * canopy_sky * ao;

        // Ambient Dielectric / Metallic Sky Reflection (especially strong on puddles, metals, ice, glass)
        let n_dot_v = saturate_f(dot(world_n, view_dir));
        let amb_fresnel = f_schlick_roughness(n_dot_v, f0, roughness);
        let refl_ray = reflect(-view_dir, world_n);
        let env_refl_sky = eval_physical_sky(vec3<f32>(refl_ray.x, max(refl_ray.y, 0.02), refl_ray.z), false);
        let env_spec = env_refl_sky * amb_fresnel * sky_vis * smoothstep(0.85, 0.10, roughness) * ao;

        // Subtle indirect cave/indoor bounce baseline so unlit caves respect Brightness setting
        let cave_floor = base_albedo * (0.004 + frame.brightness * 0.012 + frame.night_vision * 0.24) * ao;

        total_light += sun_contrib + kd * base_albedo * sky_ambient + env_spec + cave_floor;
    } else if frame.dimension == 1 {
        // The End: Directional golden-amber Gargantua accretion-disk illumination + Cosmic indigo-violet void fill + GGX PBR specular!
        let bh_l = normalize(END_BH_DIR);
        let kd = (vec3<f32>(1.0) - f0) * (1.0 - metallic);
        let n_dot_bh = max(dot(world_n, bh_l), 0.0);
        let wrap_bh  = saturate_f((dot(world_n, bh_l) + 0.25) / 1.25);

        let bh_rad = vec3<f32>(1.38, 0.90, 0.46) * end_disk_intensity * end_ambient_light * select(0.18, 1.0, end_black_hole);
        let end_diff = kd * base_albedo * mix(n_dot_bh, wrap_bh, 0.35);
        let end_spec = eval_ggx_specular(world_n, view_dir, bh_l, roughness, f0);
        let bh_direct = (end_diff + end_spec) * bh_rad * ao;

        // Hemispheric Cosmic Ambient: cool indigo-amethyst shadow fill + warm lit End-stone bounce
        let hemi_up = world_n.y * 0.5 + 0.5;
        let void_hemi = mix(vec3<f32>(0.11, 0.09, 0.16), vec3<f32>(0.14, 0.11, 0.24), hemi_up)
                      * (end_ambient_light + frame.brightness * 0.25 + frame.night_vision * 2.2);
        let end_amb = kd * base_albedo * void_hemi * ao;

        // Fresnel environment reflection of Gargantua & End cosmos on Obsidian, Purpur, Crystals & Metals!
        let n_dot_v = saturate_f(dot(world_n, view_dir));
        let amb_fresnel = f_schlick_roughness(n_dot_v, f0, roughness);
        let refl_ray = reflect(-view_dir, world_n);
        let env_end_sky = eval_end_sky(refl_ray, false);
        let end_env_spec = env_end_sky * amb_fresnel * smoothstep(0.88, 0.08, roughness) * ao * 1.25;

        total_light += bh_direct + end_amb + end_env_spec;
    } else {
        // Nether & modded dimensions: directional face shading + rich vanilla lightmap
        let dim_shade = 0.72 + 0.28 * saturate_f(world_n.y * 0.5 + 0.5);
        total_light += base_albedo * input.lightmap * dim_shade * ao;
    }

    // 7. Colored Block Light & Dynamic Lights (with subtle specular highlight from nearby torches!)
    let block_rad = eval_block_illumination(input.position, input.light.x, input.lightmap, input.colored_light);
    let block_spec_boost = mix(1.0, 1.45, smoothness * (1.0 - roughness));
    total_light += base_albedo * block_rad * ao * block_spec_boost;

    // 8. Emissive Light Sources, LabPBR Emission & Selective Mineral-Vein Ore Glow
    if input.emission > 0.001 {
        let tex_max = max(input.albedo.r, max(input.albedo.g, input.albedo.b));
        // Highlight bright filament/flame texels strongly while keeping dark metal frames readable
        let filament = smoothstep(0.18, 0.72, tex_max);
        total_light += base_albedo * input.emission * (0.75 + 2.35 * filament);
    }

    if pbr_emissive > 0.001 {
        total_light += base_albedo * pbr_emissive * 2.8;
    }

    if emissive_ores && mat == MAT_ORE {
        let c = input.albedo.rgb;
        let max_c = max(c.r, max(c.g, c.b));
        let min_c = min(c.r, min(c.g, c.b));
        let chroma = max_c - min_c;
        // Detect colored mineral veins (diamond, emerald, lapis, redstone, gold, copper)
        // or bright quartz/debris highlights while ignoring neutral grey stone/deepslate!
        let vein_mask = saturate_f(smoothstep(0.085, 0.24, chroma) + smoothstep(0.52, 0.78, max_c) * 0.65);
        total_light += base_albedo * vein_mask * ore_glow_strength * 1.45;
    }

    if mat == MAT_BIOLUM {
        let bio_max = max(input.albedo.g, input.albedo.b);
        let bio_mask = smoothstep(0.22, 0.62, bio_max);
        total_light += base_albedo * bio_mask * 0.95;
    }

    // 9. Stained Glass & Ice Translucent Optics
    var out_alpha = input.albedo.a;
    if input.translucent {
        let n_dot_v = saturate_f(dot(world_n, view_dir));
        let glass_fresnel = 0.04 + 0.96 * pow5(1.0 - n_dot_v);
        out_alpha = clamp(max(input.albedo.a, glass_fresnel * 0.65), 0.08, 0.98);
    } else {
        // Export world normal, smoothness, and SSR weight (puddles + smooth polished/metallic blocks)
        let ssr_eligible = saturate_f(max(puddle_amount, smoothstep(0.62, 0.88, smoothness) * 0.75));
        set_surface(world_n, smoothness, ssr_eligible);
    }

    // 10. Aerial Perspective & Environmental Fog
    let final_rgb = apply_aerial_fog(max(total_light, vec3<f32>(0.0)), input.position);
    return Surface(vec4<f32>(final_rgb, out_alpha));
}

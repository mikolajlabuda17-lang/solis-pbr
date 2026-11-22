// ============================================================================
// Solis PBR — Display Transform Stage (`[tonemap]`): AgX, ACES & PBR Neutral
// ============================================================================

// 6th-order polynomial contrast curve for AgX (Troy Sobotka / Benjamin Wrensch)
fn agx_contrast_poly(x: vec3<f32>) -> vec3<f32> {
    let x2 = x * x;
    let x4 = x2 * x2;
    return 15.5 * x4 * x2
         - 40.14 * x4 * x
         + 31.96 * x4
         - 6.868 * x2 * x
         + 0.4298 * x2
         + 0.1191 * x
         - 0.00232;
}

fn tonemap_agx_sdr(hdr: vec3<f32>) -> vec3<f32> {
    let agx_inset = mat3x3<f32>(
        vec3<f32>(0.842479062253094,  0.0423282422610123, 0.0423756549057051),
        vec3<f32>(0.0784335999999992, 0.878468636469772,  0.0784336),
        vec3<f32>(0.0792237451477643, 0.0791661274605434, 0.879142973793104)
    );
    let agx_outset = mat3x3<f32>(
        vec3<f32>( 1.19687900512017,   -0.0528968517574562, -0.0529716355144438),
        vec3<f32>(-0.0980208811401368,  1.15190312990417,   -0.0980434501171241),
        vec3<f32>(-0.0990297440797205, -0.0989611768448433,  1.15107367264116)
    );

    var val = agx_inset * max(hdr, vec3<f32>(1e-10));
    let min_ev = -12.47393;
    let max_ev = 4.026069;
    val = clamp((log2(val) - vec3<f32>(min_ev)) / (max_ev - min_ev), vec3<f32>(0.0), vec3<f32>(1.0));
    val = agx_contrast_poly(val);

    // Subtle "Punchy" chroma restoration in perceptual space before linear EOTF
    let lum_p = dot(val, vec3<f32>(0.2126, 0.7152, 0.0722));
    val = lum_p + (val - lum_p) * 1.08;

    val = agx_outset * val;
    return pow(clamp(val, vec3<f32>(0.0), vec3<f32>(1.0)), vec3<f32>(2.2));
}

// ACES Fitted (Stephen Hill RRT + ODT matrices)
fn tonemap_aces_sdr(hdr: vec3<f32>) -> vec3<f32> {
    let aces_in = mat3x3<f32>(
        vec3<f32>(0.59719, 0.07600, 0.02840),
        vec3<f32>(0.35458, 0.90834, 0.13383),
        vec3<f32>(0.04823, 0.01566, 0.83777)
    );
    let aces_out = mat3x3<f32>(
        vec3<f32>( 1.60475, -0.10208, -0.00327),
        vec3<f32>(-0.53108,  1.10813, -0.07276),
        vec3<f32>(-0.07367, -0.00605,  1.07602)
    );
    let v = aces_in * max(hdr, vec3<f32>(0.0));
    let a = v * (v + vec3<f32>(0.0245786)) - vec3<f32>(0.000090537);
    let b = v * (0.983729 * v + vec3<f32>(0.4329510)) + vec3<f32>(0.238081);
    return saturate_v3(aces_out * (a / max(b, vec3<f32>(1e-6))));
}

// Khronos PBR Neutral Tonemapper
fn tonemap_neutral_sdr(hdr: vec3<f32>) -> vec3<f32> {
    var color = max(hdr, vec3<f32>(0.0));
    let start_compression = 0.80 - 0.04;
    let desaturation = 0.15;

    let x = min(color.r, min(color.g, color.b));
    let offset = select(0.04, x - 6.25 * x * x, x < 0.08);
    color -= vec3<f32>(offset);

    let peak = max(color.r, max(color.g, color.b));
    if peak < start_compression {
        return saturate_v3(color);
    }

    let d = 1.0 - start_compression;
    let new_peak = 1.0 - (d * d) / (peak + d - start_compression);
    color *= new_peak / max(peak, 1e-6);

    let g = 1.0 - 1.0 / (desaturation * (peak - new_peak) + 1.0);
    return saturate_v3(mix(color, vec3<f32>(new_peak), g));
}

fn tonemap(input: TonemapInput) -> vec3<f32> {
    let hdr = max(input.color, vec3<f32>(0.0));

    var mapped = vec3<f32>(0.0);
    if tonemap_operator == 0u {
        mapped = tonemap_agx_sdr(hdr);
    } else if tonemap_operator == 1u {
        mapped = tonemap_aces_sdr(hdr);
    } else {
        mapped = tonemap_neutral_sdr(hdr);
    }

    // Native HDR Display Headroom Extension (frame.hdr == 1u, headroom > 1.0)
    let headroom = max(frame.headroom, 1.0);
    if frame.hdr == 1u && headroom > 1.02 {
        let extra_room = headroom - 1.0;
        let highlight = max(hdr - vec3<f32>(0.72), vec3<f32>(0.0));
        // Inset highlight chroma slightly so super-white sunlight doesn't clip individual primaries harshly
        let hi_lum = luma(highlight);
        let hi_inset = mix(highlight, vec3<f32>(hi_lum), 0.25);
        let hdr_lift = extra_room * (vec3<f32>(1.0) - exp(-hi_inset / (extra_room * 1.15)));
        mapped += hdr_lift;
    }

    // Tiny blue-noise / IGN dither (1/512 LSB) to prevent 8-bit SDR sky gradient banding
    let dither = (interleaved_gradient_noise(input.pixel) - 0.5) * (1.0 / 512.0);
    return clamp(mapped + vec3<f32>(dither), vec3<f32>(0.0), vec3<f32>(headroom));
}

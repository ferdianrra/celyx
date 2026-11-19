//
//  Star.metal
//  StarKit — procedural, physically-inspired star renderer for SwiftUI (iOS 17+)
//
//  Used by StarView.swift via ShaderLibrary.starSurface(...).
//  Make sure this file is in your app target (Target Membership).
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - Noise

static float hash3(float3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
static float hash2(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

static float noise3(float3 x) {
    float3 i = floor(x); float3 f = fract(x); f = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
    return mix(mix(mix(hash3(i), hash3(i + float3(1,0,0)), f.x),
                   mix(hash3(i + float3(0,1,0)), hash3(i + float3(1,1,0)), f.x), f.y),
               mix(mix(hash3(i + float3(0,0,1)), hash3(i + float3(1,0,1)), f.x),
                   mix(hash3(i + float3(0,1,1)), hash3(i + float3(1,1,1)), f.x), f.y), f.z);
}

static float fbm(float3 p) {
    float a = 0.5; float s = 0.0;
    for (int i = 0; i < 5; i++) { s += a * noise3(p); p = p * 2.03 + float3(1.7, 9.2, 3.1); a *= 0.5; }
    return s;
}

static float2 worley(float3 p, float t) {
    float3 i = floor(p); float3 f = fract(p);
    float d1 = 8.0; float d2 = 8.0;
    for (int x = -1; x <= 1; x++)
    for (int y = -1; y <= 1; y++)
    for (int z = -1; z <= 1; z++) {
        float3 b = float3(float(x), float(y), float(z));
        float3 h = float3(hash3(i + b), hash3(i + b + float3(17.1, 3.3, 9.7)), hash3(i + b + float3(5.7, 23.1, 1.9)));
        float3 o = 0.5 + 0.4 * sin(t * 0.35 + 6.2831 * h);
        float3 rr = b + o - f;
        float d = dot(rr, rr);
        if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
    }
    return float2(sqrt(d1), sqrt(d2));
}

static float3 rotX(float3 v, float a) { float c = cos(a); float s = sin(a); return float3(v.x, c*v.y - s*v.z, s*v.y + c*v.z); }
static float3 rotY(float3 v, float a) { float c = cos(a); float s = sin(a); return float3(c*v.x + s*v.z, v.y, -s*v.x + c*v.z); }

static float3 starfield(float2 uv, float t) {
    float3 c = float3(0.0);
    for (int l = 0; l < 2; l++) {
        float scale = (l == 0) ? 22.0 : 48.0;
        float2 g = uv * scale + float(l) * 17.0;
        float2 id = floor(g);
        float2 f = fract(g) - 0.5;
        float h = hash2(id);
        if (h > 0.90) {
            float2 o = float2(hash2(id + 1.3), hash2(id + 7.1)) - 0.5;
            float d = length(f - o * 0.7);
            float b = (h - 0.90) / 0.10;
            float tw = 0.65 + 0.35 * sin(t * (0.8 + h * 3.0) + h * 40.0);
            float3 tint = mix(float3(1.0, 0.82, 0.68), float3(0.75, 0.85, 1.0), hash2(id + 3.7));
            c += tint * (1.0 - smoothstep(0.0, 0.09, d)) * b * tw * ((l == 0) ? 1.0 : 0.55);
        }
    }
    return c;
}

// MARK: - Star

// p: centered coordinates, shorter side = 1 (so the view spans -0.5…0.5).
// Returns premultiplied RGBA.
static float4 starCore(float2 p, float2 fragPos, float px, float t, float2 tilt,
                       float3 deep, float3 core, float3 glowCol,
                       float turb, float glowAmt, float pulseAmt, float hot, float spotAmt,
                       float spikes, float starfieldAmt, float opaque, float radius, float granAmt) {
    float beat = sin(t * 1.2566);                       // 5 s breathing cycle
    float pulse = 1.0 + pulseAmt * 0.12 * beat;
    float R = radius * (1.0 + 0.012 * max(pulseAmt - 0.6, 0.0) * sin(t * 0.6283));
    float r = length(p) / R;
    float ang = atan2(p.y, p.x);
    float d = max(r - 1.0, 0.0);
    float edgeFade = mix(1.0 - smoothstep(0.38, 0.5, length(p)), 1.0, opaque);

    // background (only when opaque)
    float3 bg = float3(0.012, 0.014, 0.040) + glowCol * 0.05 * exp(-length(p) * 2.5);
    bg += starfield(p - tilt * 0.03, t) * starfieldAmt * smoothstep(0.9, 1.6, r);
    bg *= opaque;

    // corona: streamers flowing outward, inner glow, wide bloom
    float a1 = fbm(float3(cos(ang) * 1.6, sin(ang) * 1.6, t * 0.05));
    float a2 = fbm(float3(cos(ang) * 4.5, sin(ang) * 4.5, d * 2.5 - t * 0.18));
    float streak = a1 * a1 * 1.8 + a2 * 0.55;
    float corona = exp(-d * 3.2 / glowAmt) * (0.3 + streak) * pulse;
    float inner = exp(-d * 16.0);
    float bloom = 0.22 / (1.0 + pow(d * 5.0 / glowAmt, 2.0)) * pulse;
    float3 outc = bg + glowCol * (corona * 0.95 * glowAmt + inner * 1.3 + bloom * 0.7 * glowAmt) * edgeFade;

    float disk = 0.0;
    if (r < 1.0) {
        float z = sqrt(1.0 - r * r);
        float3 n = float3(p / R, z);
        float3 q = rotY(rotX(n, tilt.y * 0.5), t * 0.06 + tilt.x * 0.5);

        // convection: domain-warped cellular granulation
        float warp = fbm(q * 1.6 + float3(0.0, 0.0, t * 0.04));
        float3 qw = q + (float3(warp, fbm(q * 1.6 + 4.3), fbm(q * 1.6 + 8.1)) - 0.5) * 0.35;
        float sc = 12.0 * pow(turb, 1.5);
        float2 w1 = worley(qw * sc, t);
        float2 w2 = worley(qw * sc * 0.38 + 3.1, t * 0.6);
        // granAmt < 1 widens the dark lanes into soft gradients instead of sharp cracks
        float lane = 1.0 + 1.2 * (1.0 - granAmt);
        float gran = smoothstep(0.0, 0.5 * lane, w1.y - w1.x) * (0.7 + 0.3 * (1.0 - w1.x));
        float cell = smoothstep(0.0, 0.6 * lane, w2.y - w2.x) * (0.75 + 0.25 * (1.0 - w2.x));
        float big = fbm(qw * 2.2 + float3(t * 0.05, -t * 0.03, t * 0.02));
        float gc = mix(0.42, 0.1, hot) * granAmt;       // hot stars look smoother
        float I = 0.66 + (big - 0.5) * 0.6 + (gran - 0.5) * gc + (cell - 0.5) * gc * 0.6;

        // starspots (cool dwarfs) and faculae near the limb
        float spot = smoothstep(0.63, 0.72, fbm(q * 3.0 + float3(11.0, 3.0, t * 0.01)));
        I *= 1.0 - spot * spotAmt;
        float fac = smoothstep(0.55, 0.75, fbm(q * 5.0 + float3(5.0))) * pow(1.0 - z, 1.5);
        I += fac * 0.3;

        // quadratic limb darkening, cooler and redder limb
        float m = 1.0 - z;
        float limb = 1.0 - 0.5 * m - 0.2 * m * m;
        float3 surf = mix(deep, core, smoothstep(0.3, 1.0, I)) * I * 2.4;
        surf = mix(surf, deep * I * 2.0, m * 0.55);
        surf *= limb;
        surf += core * smoothstep(0.85, 1.1, I) * 0.8 * granAmt;
        surf += glowCol * smoothstep(0.9, 1.0, r) * 0.8 * mix(0.35, 1.0, granAmt);   // chromosphere rim
        surf *= 1.0 + pulseAmt * 0.05 * beat;               // disk breathes with the corona

        float aa = 1.5 * px / R;
        disk = 1.0 - smoothstep(1.0 - aa, 1.0, r);
        outc = mix(outc, surf, disk);
    }

    // diffraction spikes (as in telescope photos)
    float sx = exp(-abs(p.y) / (R * 0.012 + px)) * exp(-abs(p.x) * 3.2 / glowAmt);
    float sy = exp(-abs(p.x) / (R * 0.012 + px)) * exp(-abs(p.y) * 3.2 / glowAmt);
    outc += mix(glowCol, float3(1.0), 0.5) * (sx + sy) * spikes * 0.7 * (0.75 + 0.25 * pulse)
            * smoothstep(0.95, 1.35, r) * edgeFade;

    // hue-preserving exposure tone-map
    float L = dot(outc, float3(0.2126, 0.7152, 0.0722));
    float Lt = 1.0 - exp(-L * 1.5);
    outc = outc * (Lt / max(L, 1e-4));
    outc = mix(outc, float3(1.0), smoothstep(0.8, 1.0, Lt) * 0.55);
    outc = clamp(outc, 0.0, 1.0);

    if (opaque > 0.5) {
        outc *= mix(1.0, 1.0 - smoothstep(0.35, 1.25, length(p)), 0.6);   // vignette
        outc += (hash2(fragPos + fract(t)) - 0.5) / 255.0;                // dither
        return float4(clamp(outc, 0.0, 1.0), 1.0);
    }
    // transparent: alpha = brightness of the light, solid on the disk (premultiplied)
    float alpha = max(disk, max(outc.x, max(outc.y, outc.z)));
    return float4(outc, alpha);
}

[[ stitchable ]] half4 starSurface(float2 position, half4 color,
                                   float2 size, float time, float2 tilt,
                                   float3 deep, float3 core, float3 glowCol,
                                   float turb, float glowAmt, float pulseAmt,
                                   float hot, float spotAmt,
                                   float spikes, float starfieldAmt, float opaque, float radius,
                                   float granAmt) {
    float m = min(size.x, size.y);
    float2 p = (position - 0.5 * size) / m;
    p.y = -p.y;                                         // Metal is y-down
    float4 c = starCore(p, position, 1.0 / m, time, tilt, deep, core, glowCol,
                        turb, glowAmt, pulseAmt, hot, spotAmt, spikes, starfieldAmt, opaque, radius, granAmt);
    return half4(c);
}

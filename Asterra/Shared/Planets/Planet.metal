//
//  Planet.metal
//  Asterra — lit, rotating planet and Moon portraits for SwiftUI.
//
//  Used by PlanetView.swift via ShaderLibrary.planetSurface(...). An equirectangular
//  texture is wrapped on a sphere lit from the upper left; bodies without a texture
//  (Saturn) get procedural cloud bands. Optional atmosphere rim and ring system.
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float pHash(float2 p) { return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453); }

static float pNoise(float2 x) {
    float2 i = floor(x); float2 f = fract(x); f = f * f * (3.0 - 2.0 * f);
    return mix(mix(pHash(i), pHash(i + float2(1, 0)), f.x),
               mix(pHash(i + float2(0, 1)), pHash(i + float2(1, 1)), f.x), f.y);
}

// Procedural gas-giant bands (Saturn): soft latitudinal belts with gentle turbulence.
static float3 bands(float lat, float lon, float3 tint) {
    float wobble = 0.08 * sin(lon * 3.0 + lat * 9.0) + 0.06 * (pNoise(float2(lon * 4.0, lat * 30.0)) - 0.5);
    float b = 0.5 + 0.5 * sin((lat + wobble) * 22.0);
    float fine = pNoise(float2(lon * 2.0, lat * 80.0));
    float3 cream = tint * 1.12;
    float3 tan = tint * float3(0.82, 0.72, 0.55);
    float3 c = mix(cream, tan, b * 0.55 + fine * 0.12);
    c = mix(c, tint * float3(0.70, 0.74, 0.80), smoothstep(1.15, 1.5, abs(lat)));   // greyer poles
    return c;
}

// Ring system seen slightly from above: returns premultiplied RGBA.
static float4 ring(float2 q, float R, float3 tint) {
    float rho = length(float2(q.x, q.y / 0.30)) / R;
    if (rho < 1.28 || rho > 2.25) return float4(0.0);
    float edge = smoothstep(1.28, 1.34, rho) * (1.0 - smoothstep(2.18, 2.25, rho));
    float cassini = 1.0 - 0.85 * smoothstep(1.86, 1.89, rho) * (1.0 - smoothstep(1.95, 1.98, rho));
    float crepe = mix(0.35, 1.0, smoothstep(1.28, 1.55, rho));                  // faint inner C ring
    // irregular ringlets rather than evenly spaced grooves
    float grooves = 0.82 + 0.18 * (pNoise(float2(rho * 38.0, 0.5)) - 0.5) * 2.0
                         + 0.06 * sin(rho * 23.0);
    float a = edge * cassini * crepe * grooves * 0.9;
    float3 c = tint * float3(1.05, 0.98, 0.86) * (0.75 + 0.25 * smoothstep(1.4, 2.1, rho));
    return float4(c * a, a);
}

static float4 over(float4 top, float4 bottom) { return top + bottom * (1.0 - top.a); }

[[ stitchable ]] half4 planetSurface(float2 position, half4 color,
                                     float2 size, float time, texture2d<half> tex,
                                     float hasTexture, float3 tint,
                                     float3 atmoColor, float atmoAmt,
                                     float axialTilt, float ringAmt, float radius) {
    constexpr sampler s(address::repeat, filter::linear);
    float m = min(size.x, size.y);
    float2 p = (position - 0.5 * size) / m;
    p.y = -p.y;                                             // Metal is y-down
    float px = 1.0 / m;
    float R = radius;
    float r = length(p) / R;

    // light from the upper left, mostly from the viewer: a gibbous, clearly 3D phase
    float3 L = normalize(float3(-0.5, 0.42, 0.76));

    // ring plane rotated with the planet's axial tilt
    float ca = cos(axialTilt), sa = sin(axialTilt);
    float2 q = float2(ca * p.x + sa * p.y, -sa * p.x + ca * p.y);
    float4 ringCol = ringAmt > 0.0 ? ring(q, R, tint) * ringAmt : float4(0.0);
    // the ring's lit side faces the light; the far half sits behind the disk
    ringCol.rgb *= 0.55 + 0.45 * smoothstep(-0.6, 0.6, -q.x * 0.6 + q.y + 0.2);
    bool ringFront = q.y < 0.0;

    // atmosphere haze just outside the limb, brighter on the lit side
    float d = max(r - 1.0, 0.0);
    float litSide = smoothstep(-0.4, 0.8, dot(normalize(float3(p, 0.0001)), L));
    // also behind the limb, so the anti-aliased edge blends into haze instead of a dark seam
    float halo = exp(-d * 18.0) * atmoAmt * 0.55 * litSide;
    float4 outc = float4(atmoColor * halo, halo);

    if (!ringFront) outc = over(outc, ringCol);             // far ring behind everything

    if (r < 1.0 + 2.0 * px / R) {
        float rr = min(r, 1.0);
        float z = sqrt(max(1.0 - rr * rr, 0.0));
        float3 n = float3(p / R, z);
        float3 nt = float3(ca * n.x + sa * n.y, -sa * n.x + ca * n.y, n.z);   // body frame
        float lon = atan2(nt.x, nt.z) + time;
        float lat = asin(clamp(nt.y, -1.0, 1.0));

        float3 albedo;
        if (hasTexture > 0.5) {
            float2 uv = float2(fract(lon / 6.2831853 + 0.5), 0.5 - lat / 3.1415927);
            albedo = float3(tex.sample(s, uv).rgb);
        } else {
            albedo = bands(lat, lon, tint);
        }

        float ndl = dot(n, L);
        float terminator = smoothstep(-0.12, 0.35, ndl);   // soft day/night edge
        float diffuse = mix(pow(max(ndl, 0.0), 0.75), 1.0, 0.15) * terminator;
        // thick atmospheres darken toward the limb; airless bodies stay flat-bright
        float limb = mix(1.0, 0.55 + 0.45 * z, saturate(atmoAmt * 1.4));
        float3 surf = albedo * (0.025 + 1.05 * diffuse * limb);

        // atmospheric rim scattering on the lit side
        float rim = pow(1.0 - z, 3.0) * atmoAmt * smoothstep(-0.2, 0.5, ndl);
        surf += atmoColor * rim * 0.9;

        float disk = 1.0 - smoothstep(1.0 - 1.5 * px / R, 1.0, r);
        outc = over(float4(clamp(surf, 0.0, 1.0) * disk, disk), outc);
    }

    if (ringFront) outc = over(ringCol, outc);              // near ring in front of the disk

    return half4(clamp(outc, 0.0, 1.0));
}

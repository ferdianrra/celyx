/* Night Sea environment: standalone viewer.
   Real night sky for the viewer's place and time (stars, planets, Moon, Milky Way) over a calm sea with island silhouettes.
   No app features: no labels, no constellation lines, no taps. Drag / pinch / scroll to look around; on phones, tap once to
   use the motion sensor.

   Needs, before this file:  window.STARS (stars.js), window.FRAG (the fragment shader source), window.MW_SRC (Milky Way image URL)
   Optional:                 window.Astronomy (astronomy-engine) for planets and a more exact Sun/Moon.

   Layers, back to front:
     1. #sky  (2D canvas, transparent): stars, planets, Moon disc. Not shown directly: it is uploaded as a texture.
     2. #env  (WebGL): sky gradient + Milky Way + layer 1 + islands, and the sea that mirrors them.  <- what you see
*/
(() => {
"use strict";

/* ---------------- settings: the knobs worth turning ---------------- */
const CONFIG = {
  place: { lat: -6.2, lon: 106.85 },  // fallback place (Jakarta). Replaced by GPS if the viewer allows it.
  useGPS: true,
  fov: 72,                            // starting field of view, degrees (zoom range 24..110)
  waves: 0.14,                        // sea roughness: 0.06 calm, 0.14 default, 0.3 choppy
  islands: true,
  milkyWay: 1,                        // 0 off, 1 default
  starLimit: 6.2,                     // faintest magnitude drawn
  palette: { zenith: "#03051a", mid: "#0d1844", horizon: "#3a5d93" }, // night sky gradient
  motion: true,                       // on phones, tap once to look around by moving the phone
};

/* ---------------- small math helpers (degrees everywhere) ---------------- */
const D = Math.PI / 180;
const sin = x => Math.sin(x * D), cos = x => Math.cos(x * D), tan = x => Math.tan(x * D);
const asin = x => Math.asin(Math.max(-1, Math.min(1, x))) / D, acos = x => Math.acos(Math.max(-1, Math.min(1, x))) / D, atan2 = (y, x) => Math.atan2(y, x) / D;
const clamp = (v, a, b) => v < a ? a : v > b ? b : v, lerp = (a, b, t) => a + (b - a) * t;
const n360 = x => ((x % 360) + 360) % 360, n180 = x => { x = n360(x); return x > 180 ? x - 360 : x };
const ss = (e0, e1, x) => { const t = clamp((x - e0) / (e1 - e0), 0, 1); return t * t * (3 - 2 * t) };
const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
const vec = (az, alt) => [cos(alt) * sin(az), cos(alt) * cos(az), sin(alt)];          // horizon frame: [east, north, up]
const eqVec = (ra, dec) => [cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)];         // equatorial frame
const hexRGB = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16) / 255);

/* ---------------- astronomy ---------------- */
const AE = window.Astronomy || null;
const jdOf = ms => ms / 86400000 + 2440587.5;
function gmst(ms) { const d = jdOf(ms) - 2451545, T = d / 36525; return n360(280.46061837 + 360.98564736629 * d + 0.000387933 * T * T - T * T * T / 38710000) }
// J2000 -> date (stars in the catalogue are J2000)
function precess(ra, dec, ms) {
  const T = (jdOf(ms) - 2451545) / 36525;
  const zeta = (2306.2181 * T + 0.30188 * T * T) / 3600, z = (2306.2181 * T + 1.09468 * T * T) / 3600, th = (2004.3109 * T - 0.42665 * T * T) / 3600;
  const A = cos(dec) * sin(ra + zeta), B = cos(th) * cos(dec) * cos(ra + zeta) - sin(th) * sin(dec), C = sin(th) * cos(dec) * cos(ra + zeta) + cos(th) * sin(dec);
  return { ra: n360(atan2(A, B) + z), dec: asin(C) }
}
// low-precision Sun and Moon (good to a fraction of a degree), used when astronomy-engine is not loaded
function sunEqLow(ms) {
  const n = jdOf(ms) - 2451545; const L = n360(280.460 + 0.9856474 * n), g = n360(357.528 + 0.9856003 * n);
  const lam = L + 1.915 * sin(g) + 0.020 * sin(2 * g), eps = 23.439;
  return { ra: n360(atan2(cos(eps) * sin(lam), cos(lam))), dec: asin(sin(eps) * sin(lam)), lam }
}
function moonEqLow(ms) {
  const d = jdOf(ms) - 2451545; const L = n360(218.316 + 13.176396 * d), Mm = n360(134.963 + 13.064993 * d), F = n360(93.272 + 13.229350 * d), Dd = n360(297.850 + 12.190749 * d), Ms = n360(357.529 + 0.98560028 * d);
  const lam = n360(L + 6.289 * sin(Mm) + 1.274 * sin(2 * Dd - Mm) + 0.658 * sin(2 * Dd) + 0.214 * sin(2 * Mm) - 0.186 * sin(Ms) - 0.114 * sin(2 * F)); const bet = 5.128 * sin(F), eps = 23.439;
  return { ra: n360(atan2(sin(lam) * cos(eps) - tan(bet) * sin(eps), cos(lam))), dec: asin(sin(bet) * cos(eps) + cos(bet) * sin(eps) * sin(lam)), lam }
}
// equatorial unit vector -> horizon [east, north, up] for one instant and place
function horizXf(ms, lat, lon) {
  const L = n360(gmst(ms) + lon), cL = cos(L), sL = sin(L), sp = sin(lat), cp = cos(lat);
  return (X, Y, Z, o) => { const a = cL * X + sL * Y, b = -(sL * X - cL * Y); o[0] = b; o[1] = cp * Z - sp * a; o[2] = sp * Z + cp * a; return o }
}
const airmass = z => 1 / (Math.max(z, 0) + 0.025 * Math.exp(-11 * Math.max(z, 0)));
const K_EXT = 0.3; // magnitudes lost per airmass

/* ---------------- stars: [raHours, decDeg, mag, colourIndexBV, name] from HYG v3.8 ---------------- */
function bvRGB(bv) {
  bv = clamp(bv, -.4, 2); const t = 4600 * (1 / (0.92 * bv + 1.7) + 1 / (0.92 * bv + 0.62)) / 100;
  const r = t <= 66 ? 255 : clamp(329.7 * Math.pow(t - 60, -0.1332), 0, 255), g = t <= 66 ? clamp(99.47 * Math.log(t) - 161.12, 0, 255) : clamp(288.12 * Math.pow(t - 60, -0.0755), 0, 255), b = t >= 66 ? 255 : t <= 19 ? 0 : clamp(138.52 * Math.log(t - 10) - 305.04, 0, 255);
  return [r, g, b].map(v => Math.round(lerp(v, 255, 0.3)))
}
const T0 = Date.now();
const ST = window.STARS.map((r, i) => {
  const q = precess(r[0] * 15, r[1], T0), v = eqVec(q.ra, q.dec);
  return { i, X: v[0], Y: v[1], Z: v[2], mag: r[2], ci: r[3], name: r[4], h: [0, 0, 0], alt: 0, az: 0, em: 0 }
});
const PLANETS = ["Venus", "Jupiter", "Mars", "Saturn", "Mercury"].map(n => ({ name: n, X: 0, Y: 0, Z: 0, mag: 0, ci: n === "Mars" ? 1.4 : n === "Saturn" ? 1.0 : n === "Jupiter" ? 0.8 : 0.7, ok: false, h: [0, 0, 0] }));
for (const s of [...ST, ...PLANETS]) s.rgb = bvRGB(s.ci).join(",");

/* ---------------- state ---------------- */
const S = { obs: { ...CONFIG.place }, view: { az: 150, alt: 20, fov: CONFIG.fov }, gOff: { az: 0, alt: 0 } };
let XF = null, SOL = null;

function bodyEq(name, ms) {
  if (AE) { try { const e = AE.Equator(name, new Date(ms), new AE.Observer(S.obs.lat, S.obs.lon, 0), true, true); return { ra: e.ra * 15, dec: e.dec } } catch (_) { } }
  if (name === "Sun") return sunEqLow(ms); if (name === "Moon") return moonEqLow(ms); return null
}
function moonIllum(ms) {
  if (AE) { try { return AE.Illumination("Moon", new Date(ms)).phase_fraction } catch (_) { } }
  const e = n360(moonEqLow(ms).lam - sunEqLow(ms).lam); return (1 - cos(e)) / 2
}
// slow part (once a second): Sun, Moon, planets, and how much air dims each star
function computeSlow(ms) {
  const xf = horizXf(ms, S.obs.lat, S.obs.lon);
  const sun = bodyEq("Sun", ms), sv = eqVec(sun.ra, sun.dec), sh = xf(sv[0], sv[1], sv[2], [0, 0, 0]);
  const moon = bodyEq("Moon", ms), mv = eqVec(moon.ra, moon.dec), mh = xf(mv[0], mv[1], mv[2], [0, 0, 0]);
  for (const p of PLANETS) {
    const e = AE ? bodyEq(p.name, ms) : null; if (!e) { p.ok = false; continue }
    const v = eqVec(e.ra, e.dec); p.X = v[0]; p.Y = v[1]; p.Z = v[2]; p.ok = true;
    try { p.mag = AE.Illumination(p.name, new Date(ms)).mag } catch (_) { p.mag = 1 }
  }
  SOL = { sunAlt: asin(sh[2]), sunV: sv, sunH: sh, moonV: mv, moonH: mh, moonAlt: asin(mh[2]), illum: moonIllum(ms) };
  for (const s of ST) {
    xf(s.X, s.Y, s.Z, s.h); let em = s.mag + K_EXT * (airmass(s.h[2]) - 1);
    if (SOL.moonAlt > 0 && SOL.illum > 0.2) { const sep = acos(dot(s.h, mh)); if (sep < 14) em += SOL.illum * (14 - sep) / 14 * 1.4 }
    s.em = em
  }
}
// fast part (every frame): where everything is right now
function computeFast(ms) {
  XF = horizXf(ms, S.obs.lat, S.obs.lon);
  for (const s of ST) { XF(s.X, s.Y, s.Z, s.h); s.alt = asin(s.h[2]) }
  for (const p of PLANETS) if (p.ok) { XF(p.X, p.Y, p.Z, p.h); p.alt = asin(p.h[2]) }
  XF(SOL.moonV[0], SOL.moonV[1], SOL.moonV[2], SOL.moonH); XF(SOL.sunV[0], SOL.sunV[1], SOL.sunV[2], SOL.sunH);
}

/* ---------------- canvases and camera ---------------- */
const envCv = document.getElementById("env"), sky = document.getElementById("sky"), sctx = sky.getContext("2d");
let W = 0, H = 0, DPR = 1;
const REDUCE = matchMedia("(prefers-reduced-motion: reduce)").matches;
function resize() {
  DPR = Math.min(2, devicePixelRatio || 1); W = innerWidth; H = innerHeight;
  for (const c of [sky, envCv]) { c.width = Math.round(W * DPR); c.height = Math.round(H * DPR) }
}
// pinhole camera looking at (az, alt); the optical centre sits a little above the middle of the screen
function camera(v) {
  const f = vec(v.az, v.alt), r = [cos(v.az), -sin(v.az), 0], u = cross(r, f);
  return { f, r, u, foc: (Math.min(W, H) * 0.62) / Math.tan(v.fov * D / 2), cx: W / 2, cy: H * 0.47 }
}
function proj(c, p) { const z = dot(p, c.f); if (z < 0.06) return null; return [c.cx + dot(p, c.r) / z * c.foc, c.cy - dot(p, c.u) / z * c.foc] }
const inV = (p, m) => p && p[0] > -m && p[0] < W + m && p[1] > -m && p[1] < H + m;

/* ---------------- 2D star layer ---------------- */
const GLOWK = [-0.2, 0.15, 0.45, 0.8, 1.2, 1.6];
const GLOW = GLOWK.map(b => {
  const c = bvRGB(b).join(","), cv = document.createElement("canvas"); cv.width = cv.height = 96; const x = cv.getContext("2d"); const g = x.createRadialGradient(48, 48, 0, 48, 48, 48);
  g.addColorStop(0, "rgba(255,255,255,1)"); g.addColorStop(.07, "rgba(" + c + ",.85)"); g.addColorStop(.22, "rgba(" + c + ",.24)"); g.addColorStop(.55, "rgba(" + c + ",.05)"); g.addColorStop(1, "rgba(" + c + ",0)");
  x.fillStyle = g; x.fillRect(0, 0, 96, 96); return cv
});
const glowOf = s => s.glow || (s.glow = GLOW[GLOWK.reduce((bi, v, i) => Math.abs(v - s.ci) < Math.abs(GLOWK[bi] - s.ci) ? i : bi, 0)]);
const starR = (m, f) => clamp(3.0 - 0.55 * m, 0.8, 5) * f;

function drawStars(now, c) {
  const ctx = sctx; ctx.setTransform(DPR, 0, 0, DPR, 0, 0); ctx.clearRect(0, 0, W, H);
  const fz = Math.sqrt(72 / S.view.fov), lim = CONFIG.starLimit;
  for (const s of ST) {
    if (s.alt < 1 || s.em > lim) continue; const p = proj(c, s.h); if (!inV(p, 24)) continue;
    const a = clamp((lim - s.em) / 1.1 + 0.35, 0.35, 1), tw = REDUCE ? 1 : 0.9 + 0.1 * Math.sin(now / 290 + s.i * 1.7), r = starR(s.mag, fz) * tw;
    if (s.mag < 3.4) { const gr = r * (s.mag < 1 ? 8 : s.mag < 2 ? 6 : 4.5); ctx.globalAlpha = (s.mag < 1 ? 0.9 : 0.6) * a; ctx.drawImage(glowOf(s), p[0] - gr, p[1] - gr, gr * 2, gr * 2); ctx.globalAlpha = 1 }
    if (s.mag < 1.2) { const L = r * (s.mag < 0 ? 8 : 6); ctx.strokeStyle = "rgba(" + s.rgb + "," + (0.28 * a) + ")"; ctx.lineWidth = 0.6; ctx.beginPath(); ctx.moveTo(p[0] - L, p[1]); ctx.lineTo(p[0] + L, p[1]); ctx.moveTo(p[0], p[1] - L); ctx.lineTo(p[0], p[1] + L); ctx.stroke() }
    ctx.fillStyle = "rgba(" + s.rgb + "," + a + ")"; ctx.beginPath(); ctx.arc(p[0], p[1], r, 0, 7); ctx.fill();
    if (r > 1.7) { ctx.fillStyle = "rgba(255,255,255," + (0.9 * a) + ")"; ctx.beginPath(); ctx.arc(p[0], p[1], r * 0.45, 0, 7); ctx.fill() }
  }
  for (const pl of PLANETS) {           // planets: steady discs, no twinkle
    if (!pl.ok || pl.alt < 2) continue; const p = proj(c, pl.h); if (!inV(p, 20)) continue;
    const r = clamp(3.4 - 0.5 * pl.mag, 2, 5.2) * fz; ctx.globalAlpha = 0.8; ctx.drawImage(glowOf(pl), p[0] - r * 6, p[1] - r * 6, r * 12, r * 12); ctx.globalAlpha = 1;
    ctx.fillStyle = "rgba(" + pl.rgb + ",1)"; ctx.beginPath(); ctx.arc(p[0], p[1], r, 0, 7); ctx.fill()
  }
  drawMoon(ctx, c);
}
// Moon: halo + disc with the right phase, lit side turned toward the Sun
function drawMoon(ctx, c) {
  if (SOL.moonAlt < -1) return; const p = proj(c, SOL.moonH); if (!p) return; const r = Math.max(7, c.foc * tan(0.26)), k = SOL.illum;
  const g = ctx.createRadialGradient(p[0], p[1], r * .8, p[0], p[1], r * 10); g.addColorStop(0, "rgba(200,215,255," + (0.08 + 0.3 * k) + ")"); g.addColorStop(1, "rgba(200,215,255,0)");
  ctx.fillStyle = g; ctx.beginPath(); ctx.arc(p[0], p[1], r * 10, 0, 7); ctx.fill();
  const sp = proj(c, SOL.sunH); const ang = sp ? Math.atan2(sp[1] - p[1], sp[0] - p[0]) : 0;
  ctx.save(); ctx.translate(p[0], p[1]); ctx.fillStyle = "rgba(28,34,62,.95)"; ctx.beginPath(); ctx.arc(0, 0, r, 0, 7); ctx.fill(); ctx.rotate(ang);
  const e = Math.acos(clamp(1 - 2 * k, -1, 1)), rx = r * Math.abs(Math.cos(e)); ctx.beginPath(); ctx.arc(0, 0, r, -Math.PI / 2, Math.PI / 2, false);
  if (k >= 0.5) ctx.ellipse(0, 0, rx, r, 0, Math.PI / 2, Math.PI * 1.5, false); else ctx.ellipse(0, 0, rx, r, 0, Math.PI / 2, -Math.PI / 2, true); ctx.closePath();
  const lg = ctx.createRadialGradient(-r * .3, -r * .3, r * .1, 0, 0, r * 1.05); lg.addColorStop(0, "#ffffff"); lg.addColorStop(.7, "#e7ebf6"); lg.addColorStop(1, "#b3bccf"); ctx.fillStyle = lg; ctx.fill(); ctx.restore()
}

/* ---------------- WebGL: the environment shader ---------------- */
const GLR = (() => {
  let gl = null; try { gl = envCv.getContext("webgl", { alpha: true, premultipliedAlpha: true, antialias: false, depth: false, stencil: false }) } catch (_) { }
  if (!gl) return null;
  const mk = (t, src) => { const o = gl.createShader(t); gl.shaderSource(o, src); gl.compileShader(o); if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) { console.warn(gl.getShaderInfoLog(o)); return null } return o };
  const vs = mk(gl.VERTEX_SHADER, "attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}"), fs = mk(gl.FRAGMENT_SHADER, window.FRAG); if (!vs || !fs) return null;
  const pr = gl.createProgram(); gl.attachShader(pr, vs); gl.attachShader(pr, fs); gl.linkProgram(pr); if (!gl.getProgramParameter(pr, gl.LINK_STATUS)) return null; gl.useProgram(pr);
  const b = gl.createBuffer(); gl.bindBuffer(gl.ARRAY_BUFFER, b); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(pr, "p"); gl.enableVertexAttribArray(loc); gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
  const UL = {}; const u = n => n in UL ? UL[n] : (UL[n] = gl.getUniformLocation(pr, n));
  const tex = unit => {
    const t = gl.createTexture(); gl.activeTexture(gl.TEXTURE0 + unit); gl.bindTexture(gl.TEXTURE_2D, t); gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
    for (const [p, v] of [[gl.TEXTURE_MIN_FILTER, gl.LINEAR], [gl.TEXTURE_MAG_FILTER, gl.LINEAR], [gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE], [gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE]]) gl.texParameteri(gl.TEXTURE_2D, p, v); return t
  };
  const tStar = tex(0); gl.uniform1i(u("tStar"), 0);
  const st = { mw: false };
  const tMW = tex(4); gl.uniform1i(u("tMW"), 4);
  const img = new Image(); img.onload = () => {
    gl.activeTexture(gl.TEXTURE4); gl.bindTexture(gl.TEXTURE_2D, tMW); gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, false); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, false);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, img); st.mw = true
  }; img.src = window.MW_SRC;
  return {
    st, draw(P) {
      gl.useProgram(pr);
      for (const k in P) { const l = u(k); if (l == null) continue; const v = P[k]; if (typeof v === "number") gl.uniform1f(l, v); else if (v.length === 2) gl.uniform2fv(l, v); else gl.uniform3fv(l, v) }
      gl.activeTexture(gl.TEXTURE0); gl.bindTexture(gl.TEXTURE_2D, tStar); gl.pixelStorei(gl.UNPACK_FLIP_Y_WEBGL, true); gl.pixelStorei(gl.UNPACK_PREMULTIPLY_ALPHA_WEBGL, true);
      gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, gl.RGBA, gl.UNSIGNED_BYTE, sky);
      gl.viewport(0, 0, envCv.width, envCv.height); gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4)
    }
  }
})();
if (!GLR) { document.getElementById("nogl").hidden = false }

// The environment is always drawn as night: the Sun is pinned below the horizon, so the sun/twilight terms are zero.
function uniforms(t, c) {
  const moonUp = ss(-1, 2, SOL.moonAlt), pal = [CONFIG.palette.zenith, CONFIG.palette.mid, CONFIG.palette.horizon].map(hexRGB);
  return {
    uRes: [envCv.width, envCv.height], uDpr: DPR, uFoc: c.foc, uCx: c.cx, uCy: c.cy, uF: c.f, uR: c.r, uU: c.u,
    uZen: pal[0], uMid: pal[1], uHor: pal[2], uSun: [0, 0, -1], uMoon: SOL.moonH, uGlow: [0, 0, 0], uSunCol: [1, .45, .18],
    uIllum: SOL.illum, uMoonUp: moonUp, uMoonI: moonUp * SOL.illum, uTw: 0, uBelt: 0, uLP: 0, uNight: 1, uDay: 0, uSunI: 0, uLow: 0,
    uT: REDUCE ? 0 : t / 1000, uWave: REDUCE ? 0.06 : CONFIG.waves, uIsl: CONFIG.islands ? 1 : 0,
    uMW: GLR && GLR.st.mw ? CONFIG.milkyWay : 0, uE0: XF(1, 0, 0, [0, 0, 0]), uE1: XF(0, 1, 0, [0, 0, 0]), uE2: XF(0, 0, 1, [0, 0, 0])
  }
}

/* ---------------- looking around: drag, pinch, wheel, and (on phones) the motion sensor ---------------- */
const sens = { on: false, seen: false, az: 0, alt: 0 };
const sensorsLive = () => sens.on && sens.seen;
function onOrient(e) {
  if (e.beta == null) return; sens.seen = true;
  const head = e.webkitCompassHeading != null ? e.webkitCompassHeading : n360(360 - (e.alpha || 0));
  sens.alt = clamp(e.beta - 90, -80, 89); sens.az = n360(head)          // phone upright in portrait: beta 90 = horizon
}
async function startSensors() {
  if (sens.on) return sensorsLive();
  try { if (window.DeviceOrientationEvent && typeof DeviceOrientationEvent.requestPermission === "function") { if (await DeviceOrientationEvent.requestPermission() !== "granted") return false } } catch (_) { return false }
  addEventListener("deviceorientation", onOrient); sens.on = true; await new Promise(r => setTimeout(r, 900));
  if (!sens.seen) { removeEventListener("deviceorientation", onOrient); sens.on = false; return false }
  S.gOff = { az: 0, alt: 0 }; return true
}
const ptr = new Map(); let pinch0 = null;
envCv.addEventListener("pointerdown", e => {
  envCv.setPointerCapture(e.pointerId); ptr.set(e.pointerId, { x: e.clientX, y: e.clientY });
  if (ptr.size === 2) { const [a, b] = [...ptr.values()]; pinch0 = { d: Math.hypot(a.x - b.x, a.y - b.y), f: S.view.fov } }
});
envCv.addEventListener("pointermove", e => {
  const p = ptr.get(e.pointerId); if (!p) return; const dx = e.clientX - p.x, dy = e.clientY - p.y; p.x = e.clientX; p.y = e.clientY;
  if (ptr.size === 2 && pinch0) { const [a, b] = [...ptr.values()]; S.view.fov = clamp(pinch0.f * pinch0.d / Math.hypot(a.x - b.x, a.y - b.y), 24, 110); return }
  const k = S.view.fov / Math.min(W, H) * 1.15;
  if (sensorsLive()) { S.gOff.az = n180(S.gOff.az - dx * k); S.gOff.alt = clamp(S.gOff.alt + dy * k, -60, 60) }
  else { S.view.az = n360(S.view.az - dx * k); S.view.alt = clamp(S.view.alt + dy * k, -35, 88) }
});
const up = e => { ptr.delete(e.pointerId); if (ptr.size < 2) pinch0 = null };
envCv.addEventListener("pointerup", up); envCv.addEventListener("pointercancel", up);
envCv.addEventListener("wheel", e => { e.preventDefault(); S.view.fov = clamp(S.view.fov * (1 + e.deltaY * 0.001), 24, 110) }, { passive: false });
let kicked = false;
addEventListener("pointerup", () => { if (kicked || !CONFIG.motion) return; kicked = true; startSensors() });

/* ---------------- GPS (optional) ---------------- */
function locate() {
  if (!CONFIG.useGPS || !navigator.geolocation) return;
  try { navigator.geolocation.getCurrentPosition(p => { S.obs = { lat: p.coords.latitude, lon: p.coords.longitude }; computeSlow(Date.now()); lastSlow = performance.now() }, () => { }, { timeout: 4000, maximumAge: 6e5 }) } catch (_) { }
}

/* ---------------- main loop ---------------- */
let lastT = performance.now(), lastSlow = 0;
function frame() {
  const t = performance.now(), dt = Math.min(0.05, (t - lastT) / 1000); lastT = t;
  if (t - lastSlow > 1000) { lastSlow = t; computeSlow(Date.now()) }
  if (sensorsLive()) {
    const ta = n360(sens.az + S.gOff.az), tl = clamp(sens.alt + S.gOff.alt, -60, 88), k = 1 - Math.exp(-dt * 14);
    S.view.az = n360(S.view.az + n180(ta - S.view.az) * k); S.view.alt = lerp(S.view.alt, tl, k)
  }
  computeFast(Date.now());
  const c = camera(S.view);
  drawStars(t, c);
  if (GLR) GLR.draw(uniforms(t, c));
  requestAnimationFrame(frame)
}

/* ---------------- start ---------------- */
resize(); addEventListener("resize", resize);
computeSlow(Date.now()); computeFast(Date.now());
// open facing tonight's brightest star that is well above the horizon, with the horizon low in the frame
{
  const best = ST.filter(s => s.alt > 15).sort((a, b) => a.mag - b.mag)[0];
  if (best) S.view.az = n360(atan2(best.h[0], best.h[1]));
  const c0 = camera({ az: 0, alt: 0, fov: S.view.fov }); S.view.alt = clamp(Math.atan((H * 0.62 - c0.cy) / c0.foc) / D, 4, 30);
}
requestAnimationFrame(frame); locate();
window.NightSea = { CONFIG, state: S };   // handy for tweaking from the console
})();

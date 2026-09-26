#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec2 uTexel;
uniform vec2 uSim;
uniform vec3 uL;
uniform vec3 uSunCol;
uniform vec3 uSkyCol;
uniform vec3 uBase;
uniform vec3 uLight;
uniform vec3 uDark;
uniform float uTanE;
uniform float uRelief;
uniform float uSoft;
uniform float uAO;
uniform float uMottle;
uniform float uDepthDark;
uniform float uVig;
uniform vec4 uGrain;
uniform float uGlitter;
uniform vec2 uHeight;
uniform sampler2D uH;

out vec4 fragColor;

float grainHash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  float a = grainHash(i);
  float b = grainHash(i + vec2(1.0, 0.0));
  float c = grainHash(i + vec2(0.0, 1.0));
  float d = grainHash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float Hraw(vec2 uv) {
  vec4 s = texture(uH, uv);
  float t = s.r + s.g / 255.0;
  return t * (uHeight.y - uHeight.x) + uHeight.x;
}

float Hs(vec2 uv) {
  return Hraw(uv) * uRelief;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / uSize;
  float h = Hs(uv);
  float hl = Hs(uv - vec2(uTexel.x, 0.0));
  float hr = Hs(uv + vec2(uTexel.x, 0.0));
  float hu = Hs(uv - vec2(0.0, uTexel.y));
  float hd = Hs(uv + vec2(0.0, uTexel.y));
  vec3 n = normalize(vec3((hl - hr) * 0.5, (hu - hd) * 0.5, 1.0));

  vec2 gp = FlutterFragCoord().xy / uGrain.y;
  float gid = grainHash(floor(gp));
  float gv = vnoise(gp);
  float gx = vnoise(gp + vec2(0.5, 0.0)) - vnoise(gp - vec2(0.5, 0.0));
  float gy = vnoise(gp + vec2(0.0, 0.5)) - vnoise(gp - vec2(0.0, 0.5));
  float g2x = vnoise(gp * 0.37 + vec2(0.5, 3.1)) - vnoise(gp * 0.37 - vec2(0.5, -3.1));
  float g2y = vnoise(gp * 0.37 + vec2(3.1, 0.5)) - vnoise(gp * 0.37 + vec2(3.1, -0.5));
  vec2 facet = vec2(grainHash(floor(gp) + vec2(5.1, 1.7)), grainHash(floor(gp) + vec2(2.3, 8.9))) - 0.5;
  n = normalize(n + vec3(-(gx + 0.3 * g2x) + facet.x * 0.7, (gy + 0.3 * g2y) + facet.y * 0.7, 0.0) * uGrain.z);

  vec2 wp = uv * uSim;
  float mot = vnoise(wp / 80.0) * 0.55 + vnoise(wp / 19.0) * 0.3 + vnoise(wp / 4.0) * 0.15;
  vec3 alb = uBase * (1.0 + (mot - 0.5) * 2.0 * uMottle);
  alb *= 1.0 + ((gid * 0.55 + gv * 0.45) - 0.5) * 2.0 * uGrain.x;
  float sp = grainHash(floor(gp) + vec2(31.7, 11.3));
  if (sp < uGrain.w) {
    alb = mix(alb, uDark, 0.45 + 0.4 * grainHash(floor(gp) + vec2(3.0, 9.0)));
  } else if (sp > 1.0 - uGrain.w * 0.7) {
    alb = mix(alb, uLight, 0.55);
  }
  float hraw = h / uRelief;
  alb *= 1.0 - uDepthDark * clamp(-hraw / 4.0, 0.0, 1.0);
  alb *= 1.0 + 0.03 * clamp(hraw / 2.0, 0.0, 1.0);

  vec2 dir = normalize(uL.xy) * uTexel;
  float sh = 1.0;
  for (int i = 1; i <= 14; i++) {
    float t = float(i) * 1.35;
    float occ = Hs(uv + dir * t);
    float ray = h + t * uTanE;
    float w = 0.12 + t * uSoft;
    sh = min(sh, smoothstep(-w, w, ray - occ));
  }

  float r = 4.0;
  float avg = 0.25 * (
    Hs(uv + vec2(r, r) * uTexel) +
    Hs(uv + vec2(-r, r) * uTexel) +
    Hs(uv + vec2(r, -r) * uTexel) +
    Hs(uv + vec2(-r, -r) * uTexel)
  );
  float ao = clamp(1.0 + (h - avg) * uAO, 0.68, 1.1);

  float ndl = max(dot(n, uL), 0.0);
  vec3 col = alb * (uSunCol * ndl * sh + uSkyCol * (0.55 + 0.45 * n.z) * ao);
  float glint = step(1.0 - 0.012 * uGlitter, grainHash(floor(gp) + vec2(7.0, 3.0)));
  col += glint * sh * smoothstep(0.35, 0.8, ndl) * vec3(1.0, 0.95, 0.85) * 0.55;
  vec2 q = uv - 0.5;
  col *= 1.0 - uVig * pow(length(q * vec2(1.0, 0.8)) * 1.4, 2.4);
  fragColor = vec4(col, 1.0);
}

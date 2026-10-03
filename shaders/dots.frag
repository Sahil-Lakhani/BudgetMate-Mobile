// Port of the web login background (src/components/dot-shader-background.jsx).
// Same grid, masks, pulse and colors; the mouse-trail texture becomes a touch point.
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uResolution;
uniform float uTime;
uniform vec3 uTouch; // xy = touch position in uv space (y up), z = strength 0..1

out vec4 fragColor;

const vec3 dotColor = vec3(1.0);
const vec3 bgColor = vec3(0.0706); // #121212
const float gridSize = 100.0;
const float dotOpacity = 0.025;

vec2 coverUv(vec2 uv) {
  vec2 s = uResolution / max(uResolution.x, uResolution.y);
  vec2 newUv = (uv - 0.5) * s + 0.5;
  return clamp(newUv, 0.0, 1.0);
}

float sdfCircle(vec2 p, float r) {
  return length(p - 0.5) - r;
}

void main() {
  vec2 screenUv = FlutterFragCoord().xy / uResolution;
  screenUv.y = 1.0 - screenUv.y; // WebGL origin is bottom-left
  vec2 uv = coverUv(screenUv);

  vec2 gridUv = fract(uv * gridSize);
  vec2 gridCenter = (floor(uv * gridSize) + 0.5) / gridSize;

  float screenMask = smoothstep(0.0, 1.0, 1.0 - uv.y);
  vec2 centerDisplace = vec2(0.7, 1.1);
  float circleMaskCenter = length(uv - centerDisplace);
  float circleMaskFromCenter = smoothstep(0.5, 1.0, circleMaskCenter);

  float combinedMask = screenMask * circleMaskFromCenter;
  float circleAnimatedMask = sin(uTime * 2.0 + circleMaskCenter * 10.0);

  float touchInfluence = uTouch.z * (1.0 - smoothstep(0.0, 0.1, length(gridCenter - uTouch.xy)));

  float scaleInfluence = max(touchInfluence * 0.5, circleAnimatedMask * 0.3);
  float dotSize = min(pow(circleMaskCenter, 2.0) * 0.3, 0.3);
  float sdfDot = sdfCircle(gridUv, dotSize * (1.0 + scaleInfluence * 0.5));
  float smoothDot = smoothstep(0.05, 0.0, sdfDot);

  float opacityInfluence = max(touchInfluence * 50.0, circleAnimatedMask * 0.5);

  vec3 composition = mix(bgColor, dotColor, smoothDot * combinedMask * dotOpacity * (1.0 + opacityInfluence));
  fragColor = vec4(composition, 1.0);
}

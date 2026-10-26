#version 330
#extension GL_ARB_gpu_shader5 : enable

// KnoxBox-authored companion to the model pass. Viewpoint provides the helper
// functions at runtime; this pack contains no Viewpoint shader source files.
in vec2 vUv;
in vec3 vNormal;
in vec3 vPos;
flat in int vTexture;
flat in vec4 vTint;
flat in int vClear;
flat in vec4 vLight;
flat in int vGlass;

#include "constants.glsl"
uniform sampler2D uTextures[MODEL_TEXTURES];
uniform vec3 uEye;
uniform vec2 uAlphaRange;

#include "lib/translucent.glsl"
#include "lib/hsv.glsl"
#include "lib/fade.glsl"
#include "lib/camera_clear.glsl"
#include "lib/sun.glsl"
#include "lib/spots.glsl"
#include "lib/shade.glsl"
#include "lib/face_side.glsl"

void main() {
  cameraClear(vPos, vClear);
  fadeDither();

  vec4 texel = texture(uTextures[vTexture], vUv);
  if (vGlass != 1 || texel.a < uAlphaRange.x || texel.a >= uAlphaRange.y) discard;

  vec3 baseColor = texel.rgb;
  if (vTint.a != 0.0) baseColor = hueShift(baseColor, vTint.a);
  baseColor *= vTint.rgb;
  float distanceFromEye = length(vPos - uEye);

  // Full-bright only for movie pixels tagged by a KnoxBox frame uploader.
  if (abs(texel.a - 253.0 / 255.0) < 0.001) {
    translucent(baseColor, 1.0, distanceFromEye);
    return;
  }

  vec3 faceNormal = litSide(normalize(vNormal), facePlane(vPos), vPos, uEye);
  vec4 light = vec4(vLight.rgb, vLight.a >= 1.0 ? 1.0 : 0.0);
  float sunAmount = sunlit(vPos, faceNormal, uEye, false);
#ifdef VIEWPOINT_LAMP_SHADOW
  light.rgb = lampShadowed(light.rgb, vPos, faceNormal, light.a);
#endif
  vec3 lampColor = lamps(vPos, faceNormal);
  vec3 lampBoost = min(lampColor, light.rgb * 1.35 + vec3(0.02));
  light.rgb = max(light.rgb, lampBoost) + torches(vPos, faceNormal);
  vec3 glassColor = shade(baseColor, light, faceNormal, sunAmount);
  glassColor += baseColor * spots(vPos, faceNormal, false);
  translucent(glassColor, texel.a, distanceFromEye);
}

#version 330
#extension GL_ARB_gpu_shader5 : enable

// KnoxBox-authored Viewpoint model pass. The included helpers are supplied by
// Viewpoint at runtime; this pack does not distribute their source files.
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
uniform float uGlassOpaque;
uniform int uWireframe;
uniform int uModelFilter;

layout(location = 0) out vec4 gAlbedo;
layout(location = 1) out vec4 gNormal;
layout(location = 2) out vec4 gLight;
layout(location = 3) out vec4 gVelocity;

#include "lib/motion.glsl"
#include "lib/hsv.glsl"
#include "lib/lanczos.glsl"
#include "lib/fade.glsl"
#include "lib/camera_clear.glsl"
#include "lib/face_side.glsl"

void main() {
  cameraClear(vPos, vClear);
  fadeDither();

  vec2 dimensions = vec2(textureSize(uTextures[vTexture], 0));
  vec2 horizontal = dFdx(vUv);
  vec2 vertical = dFdy(vUv);
  vec4 pixel;
  if (uModelFilter == FILTER_LANCZOS && magnified(dimensions, horizontal, vertical)) {
    pixel = lanczos(uTextures[vTexture], vUv, ivec2(0), ivec2(dimensions) - 1, true);
  } else if (uModelFilter == FILTER_SHARP) {
    pixel = textureGrad(uTextures[vTexture], sharpUv(vUv, dimensions, horizontal, vertical), horizontal, vertical);
  } else {
    pixel = texture(uTextures[vTexture], vUv);
  }

  bool transparent = pixel.a < 0.01;
  if (vGlass == 1) {
    transparent = pixel.a < uGlassOpaque;
  } else if (pixel.a < 0.99) {
    transparent = transparent || pixel.a <= fadeNoise();
  }
  if (transparent && uWireframe == 0) discard;

  vec3 painted = pixel.rgb;
  if (vTint.a != 0.0) painted = hueShift(painted, vTint.a);

  // The KnoxBox frame bridges tag active TV and projector movie pixels.
  // Viewpoint's default lighting pass displays material 0.25 at full brightness.
  bool projection = abs(pixel.a - 253.0 / 255.0) < 0.001;
  float materialId = projection ? 0.25 : 31.0 / 255.0;
  vec3 facing = litSide(normalize(vNormal), facePlane(vPos), vPos, uEye);

  gAlbedo = vec4(painted * vTint.rgb, materialId);
  gNormal = vec4(facing, vLight.a >= 1.0 ? 1.0 : 0.0);
  gLight = vLight;
  gVelocity = motion();

  if (uWireframe == 2) {
    gAlbedo.rgb = vec3(0.45, 0.65, 1.0);
    gLight = vec4(1.0);
  }
}

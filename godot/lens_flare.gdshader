shader_type spatial;
render_mode unshaded, blend_premul_alpha, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

#include "res://water_waves.gdshaderinc"
global uniform float osc_natural_surface;
global uniform bool osc_lens_flares_enabled;
global uniform vec4 osc_surface_waves;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D ripple_normals : hint_normal, repeat_enable, filter_linear_mipmap;
uniform vec3 flare_color : source_color = vec3(1.0);
uniform float brightness = 0.0;
uniform float reach = 20.0;
uniform float diameter = 1.0;
uniform float cone_cosine = -1.0;
uniform float forward_sign = 1.0;
uniform bool solar = false;
uniform bool lunar = false;
varying vec2 source_uv;
varying float source_depth;
varying float visibility;
varying float solar_above_water;

void vertex() {
 vec3 eye = INV_VIEW_MATRIX[3].xyz;
 vec3 origin = MODEL_MATRIX[3].xyz;
 visibility = 1.0;
 solar_above_water = 0.0;
 if (solar) {
  vec3 sun = normalize(MODEL_MATRIX[2].xyz);
  visibility *= smoothstep(0.0,0.18,sun.y);
  // Match the water shader's refracted sky within Snell's window.
  if (eye.y < osc_natural_surface) {
   sun.xz /= 1.25;
   sun.y = sqrt(max(0.0,1.0-dot(sun.xz,sun.xz)));
   float water_depth = osc_natural_surface-eye.y;
   origin = eye+sun*max(0.1,water_depth/max(sun.y,0.001));
   visibility *= exp(-water_depth*0.045);
  } else {
   solar_above_water = 1.0;
   origin = eye+sun*1000.0;
  }
 } else {
  vec3 to_eye = eye-origin;
  float distance_to_eye = length(to_eye);
  vec3 facing = normalize(MODEL_MATRIX[2].xyz)*forward_sign;
  float angle_fade = cone_cosine < -0.5 ? 1.0 : smoothstep(cone_cosine,min(1.0,cone_cosine+0.12),dot(facing,normalize(to_eye)));
  visibility = angle_fade*(1.0-smoothstep(reach*0.35,reach,distance_to_eye));
 }
 vec4 view_origin = VIEW_MATRIX*vec4(origin,1.0);
 vec4 clip = PROJECTION_MATRIX*view_origin;
 source_uv = clip.xy/clip.w*0.5+0.5;
 source_depth = -view_origin.z;
 visibility *= step(0.0,source_depth)*step(0.0,source_uv.x)*step(source_uv.x,1.0)*step(0.0,source_uv.y)*step(source_uv.y,1.0);
 // Optical reflections follow the axis through source and image centre.
 vec2 opposite = vec2(0.5)+(vec2(0.5)-source_uv)*1.25;
 vec2 margin = vec2(0.28*VIEWPORT_SIZE.y/VIEWPORT_SIZE.x,0.28);
 vec2 low = max(vec2(0.0),min(source_uv,opposite)-margin);
 vec2 high = min(vec2(1.0),max(source_uv,opposite)+margin);
 POSITION = vec4(mix(low,high,UV)*2.0-1.0,0.0,1.0);
}

vec3 ghost(vec2 pixel,vec2 source,float aspect,float along,float radius,vec3 tint,float strength) {
 vec2 centre = mix(source,vec2(0.5),along);
 vec2 offset = (pixel-centre)*vec2(aspect,1.0);
 float r = length(offset)/radius;
 float disc = (1.0-smoothstep(0.15,1.0,r))*0.35;
 float edge = (r-0.8)*12.0;
 float rim = exp(-edge*edge);
 return tint*(disc+rim)*strength;
}

void fragment() {
 if (!lunar && !osc_lens_flares_enabled) discard;
 if (visibility*brightness < 0.001) discard;
 bool submerged_moon = lunar && solar_above_water < 0.5;
 vec2 depth_uv = submerged_moon ? SCREEN_UV : source_uv;
 float depth = texture(depth_texture,depth_uv).r;
 #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
 vec3 ndc = vec3(depth_uv,depth)*2.0-1.0;
 #else
 vec3 ndc = vec3(depth_uv*2.0-1.0,depth);
 #endif
 vec4 hit = INV_PROJECTION_MATRIX*vec4(ndc,1.0);
 float scene_depth = -hit.z/hit.w;
 // The water is the solar aperture. Roofs/terrain below it block the
 // entire effect, including reflections elsewhere on screen.
 float unobstructed = step(source_depth-(solar ? 0.15 : 0.04),scene_depth);
 if (solar_above_water > 0.5) {
  #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
  vec4 endpoint_a = INV_PROJECTION_MATRIX*vec4(source_uv*2.0-1.0,-1.0,1.0);
  #else
  vec4 endpoint_a = INV_PROJECTION_MATRIX*vec4(source_uv*2.0-1.0,0.0,1.0);
  #endif
  vec4 endpoint_b = INV_PROJECTION_MATRIX*vec4(source_uv*2.0-1.0,1.0,1.0);
  float far_depth = max(-endpoint_a.z/endpoint_a.w,-endpoint_b.z/endpoint_b.w);
  unobstructed = step(far_depth*0.995,scene_depth);
 }
 vec2 aspect = vec2(VIEWPORT_SIZE.x/VIEWPORT_SIZE.y,1.0);
 vec2 p = (SCREEN_UV-source_uv)*aspect;
 if (submerged_moon) {
  vec3 view_ray = normalize((INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,0.5,1.0)).xyz);
  vec3 ray = mat3(INV_VIEW_MATRIX)*view_ray;
  vec3 eye = INV_VIEW_MATRIX[3].xyz;
  float distance_to_surface = (osc_natural_surface-eye.y)/max(ray.y,0.001);
  unobstructed = step(0.0,ray.y)*step(-view_ray.z*distance_to_surface-osc_surface_waves.x-0.15,scene_depth);
  if (osc_surface_waves.x > 0.0 && length(p) < 0.16) {
   vec2 point = (eye + ray*distance_to_surface).xz;
   vec3 waves = wave_sample(point,osc_surface_waves);
   vec2 detail = ripple_detail(ripple_normals,point,distance_to_surface,osc_surface_waves);
   vec3 normal = water_normal(waves.yz,detail);
   vec3 sky_ray = refract(ray,-normal,1.25);
   unobstructed *= step(0.0,sky_ray.y)*step(0.1,dot(sky_ray,sky_ray));
   // Project the ray back through a flat surface to find the displaced disc UV.
   vec2 flat_xz = sky_ray.xz/1.25;
   vec3 flat_ray = vec3(flat_xz.x,sqrt(max(0.0,1.0-dot(flat_xz,flat_xz))),flat_xz.y);
   vec4 clip = PROJECTION_MATRIX*vec4(mat3(VIEW_MATRIX)*flat_ray,0.0);
   p = (clip.xy/max(clip.w,0.001)*0.5+0.5-source_uv)*aspect;
  }
 }
 float intensity = clamp(brightness*visibility*unobstructed,0.0,1.0);
 // Emit light without replacing the scene behind the flare's screen quad.
 ALPHA = 0.0;
 if (lunar) {
  vec2 disc_position = p/0.013;
  float radius = length(disc_position);
  float edge_width = fwidth(radius);
  float disc = 1.0-smoothstep(1.0-edge_width,1.0+edge_width,radius);
  vec2 sea = (disc_position-vec2(-0.24,0.25))*vec2(1.0,1.5);
  vec2 basin = (disc_position-vec2(0.37,-0.21))*vec2(1.4,1.0);
  float surface_detail = 1.0-0.24*exp(-6.0*dot(sea,sea))-0.18*exp(-8.0*dot(basin,basin));
  float halo = exp(-radius*radius*0.30)*0.065;
  ALBEDO = mix(flare_color,vec3(1.0),0.65)*(disc*surface_detail+halo)*intensity;
 } else {
  float scale = clamp(diameter,0.8,1.4);
  p /= scale;
  float radius = length(p);
  float core = exp(-radius*radius/0.0001)*0.95;
  float halo = exp(-radius*radius/0.0025)*0.36;
  float streak = exp(-abs(p.y)/0.0015)*exp(-abs(p.x)/0.12)*0.9;
  float ring_edge = (radius-0.095)/0.006;
  float ring = exp(-ring_edge*ring_edge)*0.12;
  vec3 optics = mix(flare_color,vec3(1.0),0.55)*(core+halo+streak);
  optics += vec3(0.48,0.68,1.0)*ring;
  optics += ghost(SCREEN_UV,source_uv,VIEWPORT_SIZE.x/VIEWPORT_SIZE.y,0.55,0.026,vec3(1.0,0.68,0.22),0.18);
  optics += ghost(SCREEN_UV,source_uv,VIEWPORT_SIZE.x/VIEWPORT_SIZE.y,1.2,0.065,vec3(0.22,0.85,0.65),0.16);
  optics += ghost(SCREEN_UV,source_uv,VIEWPORT_SIZE.x/VIEWPORT_SIZE.y,1.65,0.035,vec3(0.6,0.35,0.95),0.14);
  optics += ghost(SCREEN_UV,source_uv,VIEWPORT_SIZE.x/VIEWPORT_SIZE.y,2.2,0.11,vec3(0.24,0.6,0.95),0.12);
  // Convert optical colour once, rather than gamma-dimming the opacity.
  // The solar aperture is already a bright, tonemapped sky. Squaring its
  // faint optical reflections again erased their daytime contrast in Forward+.
  // Keep the accepted local-lamp treatment; solar optics add linear radiance.
  ALBEDO = (OUTPUT_IS_SRGB ? optics : (solar ? optics*0.65 : pow(max(optics,vec3(0.0)),vec3(2.2))))*intensity;
 }
}

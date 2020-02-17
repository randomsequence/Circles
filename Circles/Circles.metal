//  Created by Johnnie Walker on 11/02/2020.

#include <metal_stdlib>
using namespace metal;

#import "MetalShared.h"

#pragma mark - Vertex Rasterisation

struct VertexIn{
  packed_float3 position;
  packed_float2 texCoord;
};

struct VertexOut{
  float4 position [[position]];
  float2 texCoord;
};

vertex VertexOut basic_vertex(
                           const device VertexIn* vertex_array [[ buffer(0) ]],
                           unsigned int vid [[ vertex_id ]]) {
  
  VertexIn vertexIn = vertex_array[vid];
  
  VertexOut vertexOut;  
  vertexOut.position = float4(vertexIn.position, 1.0);
  vertexOut.texCoord = vertexIn.texCoord;
  
  return vertexOut;
}

fragment half4 basic_fragment(VertexOut interpolated [[stage_in]],
                              texture2d<half, access::sample>  tex2D  [[texture(TextureIndexInput)]]) {
  
  constexpr sampler sampler2D(coord::normalized, address::clamp_to_zero, filter::linear);
  
  half4 color = tex2D.sample(sampler2D, interpolated.texCoord);
  return color;
}

#pragma mark - Compute

// source-over blending
static inline half4 alpha_blend(half4 src, half4 dest) {
  return src + (dest * (1.0-src.a));
}

// Rec. 709 luma values for grayscale image conversion
constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);

struct Circle {
  half2 position;
  half2 velocity;
  half4 color;
  half radius;
};

constant int CircleCount = 16;
constant Circle circles[CircleCount] = {
  {.position={0.1, 0.2}, .velocity={0.6, -.7}, .color={1.0, 0.3, 0.0, 0.8}, .radius=0.3},
  {.position={-.3, 0.4}, .velocity={-.9, 1.0}, .color={0.2, 0.3, 0.5, 0.4}, .radius=0.2},
  {.position={-.5, 0.2}, .velocity={0.3, 1.0}, .color={0.3, 0.1, 0.6, 0.9}, .radius=0.4},
  {.position={-.2, 0.2}, .velocity={0.2, -.7}, .color={0.3, 0.1, 0.6, 0.9}, .radius=0.4},
  {.position={0.5, 0.2}, .velocity={-.5, 1.0}, .color={0.3, 0.5, 0.0, 0.7}, .radius=0.4},
  {.position={-.2, -.6}, .velocity={1.0, 0.2}, .color={0.6, 0.3, 0.2, 0.5}, .radius=0.6},
  {.position={0.4, 0.3}, .velocity={0.5, 1.0}, .color={0.0, 0.9, 0.4, 0.2}, .radius=0.5},
  {.position={-.4, -.3}, .velocity={0.7, -.3}, .color={0.9, 0.3, 0.0, 0.7}, .radius=0.3},
  {.position={-.4, -.3}, .velocity={0.3, 1.0}, .color={1.0, 1.0, 1.0, 0.8}, .radius=.04},
  {.position={-.3, -.5}, .velocity={1.0, 0.5}, .color={1.0, 1.0, 1.0, 0.7}, .radius=.03},
  {.position={-.2, -.5}, .velocity={1.0, -.9}, .color={1.0, 1.0, 1.0, 0.6}, .radius=.02},
  {.position={-.4, -.3}, .velocity={0.9, 1.0}, .color={1.0, 1.0, 1.0, 0.5}, .radius=.01},
  {.position={-.3, -.3}, .velocity={0.4, 0.7}, .color={1.0, 1.0, 1.0, 0.8}, .radius=.04},
  {.position={-.2, -.5}, .velocity={1.0, 0.4}, .color={1.0, 1.0, 1.0, 0.7}, .radius=.03},
  {.position={-.1, -.4}, .velocity={0.8, -.9}, .color={1.0, 1.0, 1.0, 0.6}, .radius=.02},
  {.position={-.6, -.5}, .velocity={1.0, 0.9}, .color={1.0, 1.0, 1.0, 0.5}, .radius=.01},
};

kernel void generate_circles(texture2d<half, access::write> outTexture [[texture(TextureIndexOutput)]],
                             const array<texture2d<half, access::sample>, 4> inTextures  [[texture(TextureIndexInput)]],
                             constant int *frameCountIndex [[buffer(BufferIndexFrameCount)]],
                             uint2 gid [[thread_position_in_grid]],
                             uint2 grid [[threads_per_grid]]
//                             uint2 threadgroups [[threadgroups_per_grid]],
//                             uint2 threads_per_threadgroup [[ threads_per_threadgroup ]]
                             )
{
  const half frame = half(frameCountIndex[0]) / 60.0h;
  
  // pixel position in normalised coordinates, with 0,0 at the centre
  half2 gridh = half2(grid);
  half2 gidh = half2(-0.5) + (half2(gid) / gridh);
  gidh.x *= (gridh.x / gridh.y);

  constexpr sampler textureSampler(coord::normalized, address::mirrored_repeat, mag_filter::linear, min_filter::linear);

  half4 color = half4(0);

  half4 inColor  = inTextures[0].sample(textureSampler, float2(gidh) * 4.0);
  const half grey = dot(inColor.rgb, kRec709Luma);

  color = alpha_blend(grey, color);

  for (int i=0; i<CircleCount; i++) {
    const half2 velocity = circles[i].velocity;
    const half2 position = circles[i].position * half2(sin(frame * velocity.x), cos(frame * velocity.y));
    const half dist = distance(gidh, position);

    const float2 coordinate = float2(gidh - position);
    const half4 sampled = inTextures[i % 4].sample(textureSampler, coordinate);
    const half mono = dot(sampled.rgb, kRec709Luma);

    const half4 tinted = half4(circles[i].color.rgb * 0.5 + (circles[i].color.rgb * mono * 0.5), circles[i].color.a);

//    color = alpha_blend(sampled, color);
    
    const half opacity = step(0.0h, circles[i].radius - dist); // max(0.0h, circles[i].radius - dist);
    color = alpha_blend(tinted * opacity, color);
  }
  
  outTexture.write(color, gid);
}

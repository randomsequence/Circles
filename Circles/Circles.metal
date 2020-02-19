//  Created by Johnnie Walker on 11/02/2020.

#include <metal_stdlib>
using namespace metal;

#import "MetalShared.h"

#pragma mark - Compute

// source-over blending function
static inline half4 alpha_blend(half4 src, half4 dest) {
  return src + (dest * (1.0-src.a));
}

// Rec. 709 luma values for grayscale image conversion
constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);

/**
 
 Kernel which renders an array of Circle stucts to the current grid position in the texture.
 
 */
kernel void render_circles(texture2d<half, access::write> outTexture [[texture(TextureIndexOutput)]],
                           const array<texture2d<half, access::sample>, RenderCirclesTextureCount> inTextures  [[texture(TextureIndexInput)]],
                           constant FrameInfo *frameInfo [[buffer(BufferIndexFrameInfo)]],
                           constant Circle *circles [[buffer(BufferIndexCircleData)]],
                           uint2 gid [[thread_position_in_grid]],
                           uint2 grid [[threads_per_grid]]
                           )
{
  
  const half frame = half(frameInfo[0].FrameCount) / 60.0h;
  
  // pixel position in normalised coordinates, with 0,0 at the centre
  half2 gridh = half2(grid);
  half2 gidh = half2(-0.5) + (half2(gid) / gridh);  // fix the aspect ratio so that circles are circular
  gidh.x *= (gridh.x / gridh.y);

  constexpr sampler textureSampler(coord::normalized, address::mirrored_repeat, mag_filter::linear, min_filter::linear);
  
  half4 color = half4(0); // begin with a transparent destination

  // Sample a the first to use as a background
  half4 inColor  = inTextures[0].sample(textureSampler, float2(gidh) * 4.0);
  const half grey = dot(inColor.rgb, kRec709Luma);

  // blend the background over our destination
  color = alpha_blend(grey, color);

  const uint circleCount = frameInfo[0].CircleCount;
  
  for (uint i=0; i<circleCount; i++) {
    const half2 velocity = half2(circles[i].velocity);
    // use velocity and frame count to rotate the circle's origin about the centre of the grid
    const half2 position = half2(circles[i].origin) * half2(sin(frame * velocity.x), cos(frame * velocity.y));
    
    const float2 coordinate = float2(gidh - position); // vector from the circle to this grid point
    const uint textureIndex = circles[i].textureIndex % RenderCirclesTextureCount;
    const half4 sampled = inTextures[textureIndex].sample(textureSampler, coordinate);
    
    // do a colour calculation to simulate simple image processing
    const half mono = dot(sampled.rgb, kRec709Luma);
    const half4 circleColor = half4(circles[i].color);
    const half4 tinted = half4(circleColor.rgb * 0.5h + (circleColor.rgb * mono * 0.5h), circleColor.a);
 
    // find opacity - 0 if we're outside the circle's radius
    const half dist2 = distance_squared(gidh, position);
    const half radius = half(circles[i].radius);
    const half opacity = step(0.0h, half((radius*radius) - dist2));
    
    // blend our processed colour with the destination
    color = alpha_blend(tinted * opacity, color);
  }
  
  outTexture.write(color, gid);
}

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

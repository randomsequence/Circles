//  Created by Johnnie Walker on 11/02/2020.

#include <metal_stdlib>
using namespace metal;

#import "MetalShared.h"

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

// Rec. 709 luma values for grayscale image conversion
constant half3 kRec709Luma = half3(0.2126, 0.7152, 0.0722);

kernel void generate_circles(texture2d<half, access::read>  inTexture  [[texture(TextureIndexInput)]],
                             texture2d<half, access::write> outTexture [[texture(TextureIndexOutput)]],
                             uint2 gid [[thread_position_in_grid]],
                             uint2 threads_per_threadgroup        [[ threads_per_threadgroup ]])
{
  half4 inColor  = inTexture.read(gid);
  half grey = dot(inColor.rgb, kRec709Luma);
  outTexture.write(half4(grey, grey, grey, inColor.a), gid);
}

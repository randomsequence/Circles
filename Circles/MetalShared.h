//  Created by Johnnie Walker on 15/02/2020.

#ifndef MetalShared_h
#define MetalShared_h

#include <simd/simd.h>

#define RenderCirclesTextureCount 64

typedef enum TextureIndex
{
    TextureIndexOutput = 0,
    TextureIndexInput  = 1,
} TextureIndex;

typedef enum BufferIndex
{
    BufferIndexFrameInfo = 0,
    BufferIndexCircleAB = 1,
} BufferIndex;

struct Circle {
  simd_float4 color;
  simd_float2 origin;
  simd_float2 velocity;
  uint textureIndex;
  float radius;
};

struct FrameInfo {
  uint FrameCount;
  uint CircleCount;
};

typedef enum ABBufferID {
  ABBufferIDCircles = 0,
  ABBufferIDTextures
} ABBufferID;

#endif /* MetalShared_h */

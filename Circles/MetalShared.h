//  Created by Johnnie Walker on 15/02/2020.

#ifndef MetalShared_h
#define MetalShared_h

#include <simd/simd.h>

typedef enum TextureIndex
{
    TextureIndexOutput = 0,
    TextureIndexInput  = 1,
} TextureIndex;

typedef enum BufferIndex
{
    BufferIndexFrameCount = 0,
} BufferIndex;

#endif /* MetalShared_h */

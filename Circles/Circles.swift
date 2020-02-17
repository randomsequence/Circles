//  Created by Johnnie Walker on 11/02/2020.

import AppKit
import CoreImage
import Metal
import MetalKit
import GameKit

public class Circles : NSObject {
  
  let device: MTLDevice
  let pipeline: MTLComputePipelineState!

  var inputTextures = [MTLTexture]()
  let threadgroupSize: MTLSize

  var frameCount: Int = 0

  
  public init(device: MTLDevice) {
    self.device = device
    let library = device.makeDefaultLibrary()!
    let function = library.makeFunction(name: "render_circles")!
    pipeline = try! device.makeComputePipelineState(function: function)
    
    let loader = MTKTextureLoader(device: device)
    for name in ["cells", "jar", "morris", "salt"] {
      let inputTexture = try! loader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: [:])
      inputTextures.append(inputTexture)
    }

    let threadExecutionWidth = pipeline.threadExecutionWidth
    threadgroupSize = MTLSizeMake(threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup / threadExecutionWidth, 1);
  }

  public func generate(count: Int = 128) -> MTLBuffer {

    let noiseSource = GKPerlinNoiseSource(frequency: 0.1, octaveCount: 2, persistence: 1, lacunarity: 0.3, seed: 05535555)
    let noise = GKNoise(noiseSource)

    let circleBuffer = UnsafeMutableBufferPointer<Circle>.allocate(capacity: count)
    for i in 0..<count {
      let i_f = Float(i)
      circleBuffer[i].position = simd_float2(noise.value(atPosition: vector_float2(i_f, 0)),
                                             noise.value(atPosition: vector_float2(0, i_f)))
      let radius = abs(0.75 * noise.value(atPosition: vector_float2(-i_f, i_f)))
      circleBuffer[i].radius = radius
      circleBuffer[i].velocity = simd_float2(2.0 * (1.0-radius) * noise.value(atPosition: vector_float2(i_f, i_f+1)),
                                             2.0 * (1.0-radius) * noise.value(atPosition: vector_float2(-i_f, 2)))
      circleBuffer[i].color = simd_float4((1.0-radius) * abs(noise.value(atPosition: vector_float2(i_f*1, i_f*1))),
                                          (1.0-radius) * abs(noise.value(atPosition: vector_float2(i_f*2, i_f*2))),
                                          (1.0-radius) * abs(noise.value(atPosition: vector_float2(i_f*3, i_f*3))),
                                          0.5 + abs(0.5 * noise.value(atPosition: vector_float2(i_f, 5))))
    }

    defer {
      circleBuffer.deallocate()
    }

    let length = MemoryLayout<Circle>.size * count
    return device.makeBuffer(bytes: circleBuffer.baseAddress!, length: length, options: MTLResourceOptions.storageModeManaged)!
  }
  
  public func render(commands: MTLCommandBuffer, texture: MTLTexture, circles: MTLBuffer) {
    let computeEncoder = commands.makeComputeCommandEncoder()!
            
    computeEncoder.setComputePipelineState(pipeline)
    computeEncoder.setBytes(&frameCount, length: MemoryLayout<Int>.size, index: Int(BufferIndexFrameCount.rawValue));
//    computeEncoder.setTexture(inputTexture, index: Int(TextureIndexInput.rawValue))
    let startIndex = Int(TextureIndexInput.rawValue)
    computeEncoder.setBuffer(circles, offset: 0, index: Int(BufferIndexCircleData.rawValue))
    computeEncoder.setTextures(inputTextures, range: startIndex..<startIndex+inputTextures.count)
    computeEncoder.setTexture(texture, index: Int(TextureIndexOutput.rawValue))
    
    let width = texture.width
    let height = texture.height
    
    let threadgroupCount = MTLSizeMake(width, height, 1)
    computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadgroupSize)

/**
     Non-uniform thread-group size is supported by all Mac GPUs, but if it weren't we'd calculate like this:
     https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf

     let threadgroupCount = MTLSizeMake((width + threadgroupSize.width - 1) / threadgroupSize.width,
                                        (height + threadgroupSize.height - 1) / threadgroupSize.height,
                                        1);
     computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
*/
    
    computeEncoder.endEncoding()
    
    frameCount += 1;
  }
}

//  Created by Johnnie Walker on 11/02/2020.

import AppKit
import CoreImage
import Metal
import MetalKit
import GameKit

public class Circles : NSObject {
  
  let device: MTLDevice
  let function: MTLFunction!
  let pipeline: MTLComputePipelineState!

  var circleBuffer: MTLBuffer? = nil

  var inputTextures = [MTLTexture]()
  let threadgroupSize: MTLSize

  var circleCount: Int = 16
  
  public init(device: MTLDevice, library: MTLLibrary) {
    self.device = device

    function = library.makeFunction(name: "render_circles")!
    pipeline = try! device.makeComputePipelineState(function: function)
    
    let loader = MTKTextureLoader(device: device)
    let options: [MTKTextureLoader.Option : Any] = [
      MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
      MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue)
                  ]
    for name in ["cells", "jar", "morris", "salt"] {
      let inputTexture = try! loader.newTexture(name: name, scaleFactor: 1.0, bundle: nil, options: options)
      inputTextures.append(inputTexture)
    }

    let threadExecutionWidth = pipeline.threadExecutionWidth
    threadgroupSize = MTLSizeMake(threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup / threadExecutionWidth, 1);
  }

  // Generates an argument buffer containing the circle data and textures
  // Note that the argument buffer does not retain any buffers it refers to
  public func generate(count: Int = 512) -> MTLBuffer {

    // use a noise source to generate sane values for an array of circles
    let noiseSource = GKPerlinNoiseSource(frequency: 0.1, octaveCount: 2, persistence: 1, lacunarity: 0.3, seed: 05535533)
    let noise = GKNoise(noiseSource)

    var circles = [Circle]()

    for i in 0..<count {
      let i_f = Float(i)
      let radius = abs(0.75 * noise.value(atPosition: vector_float2(-i_f, i_f)))
      let circle = Circle(color: simd_float4((0.25 + 0.75*(1.0-radius)) * abs(noise.value(atPosition: vector_float2(i_f*1, i_f*1))),
                                 (0.25 + 0.75*(1.0-radius)) * abs(noise.value(atPosition: vector_float2(i_f*2, i_f*2))),
                                 (0.25 + 0.75*(1.0-radius)) * abs(noise.value(atPosition: vector_float2(i_f*3, i_f*3))),
                                 0.75 + abs(0.25 * noise.value(atPosition: vector_float2(i_f, 5)))),
              origin: simd_float2(noise.value(atPosition: vector_float2(i_f, 0)),
                                  noise.value(atPosition: vector_float2(0, i_f))),
              velocity: simd_float2(0.1 + (2.0 * (1.0-radius) * noise.value(atPosition: vector_float2(i_f, i_f+1))),
                                    0.1 + (2.0 * (1.0-radius) * noise.value(atPosition: vector_float2(-i_f, 2)))),
              textureIndex: uint(abs(Float(inputTextures.count) * noise.value(atPosition: vector_float2(i_f, 6)))),
              radius: radius)
      circles.append(circle)
    }

    circles.withUnsafeBytes { ptr in
      circleBuffer = device.makeBuffer(bytes: ptr.baseAddress!, length: ptr.count, options: MTLResourceOptions.storageModeManaged)!
    }

    let argumentEncoder = function.makeArgumentEncoder(bufferIndex: Int(BufferIndexCircleAB.rawValue))
    let encodedLength = argumentEncoder.encodedLength
    let argumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength, options: .storageModeManaged)
    argumentEncoder.setArgumentBuffer(argumentBuffer, offset: 0)

    let startIndex = Int(ABBufferIDTextures.rawValue)
    argumentEncoder.setTextures(inputTextures, range: startIndex..<startIndex+inputTextures.count)
    argumentEncoder.setBuffer(circleBuffer, offset: 0, index: Int(ABBufferIDCircles.rawValue))

    argumentBuffer?.didModifyRange(0..<encodedLength)

    return argumentBuffer!
  }
  
  public func render(commands: MTLCommandBuffer, texture: MTLTexture, circlesAB: MTLBuffer, info: RenderInfo) {
    let computeEncoder = commands.makeComputeCommandEncoder()!
            
    var info = FrameInfo(FrameCount: uint(info.frameIndex), CircleCount: uint(circleCount))

    computeEncoder.setComputePipelineState(pipeline)
    computeEncoder.setBytes(&info, length: MemoryLayout<FrameInfo>.size, index: Int(BufferIndexFrameInfo.rawValue));
    computeEncoder.setBuffer(circlesAB, offset: 0, index: Int(BufferIndexCircleAB.rawValue))
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
  }
}

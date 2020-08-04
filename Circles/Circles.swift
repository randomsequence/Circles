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

  var heap: MTLHeap? = nil

  var inputTextures = [MTLTexture]()
  var heapTextures = [MTLTexture]()

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

    super.init()

    self.heap = makeHeap()
    heapTextures = copyTexturesToHeap(heap!, textures: inputTextures)
  }

  func copyTexturesToHeap(_ heap: MTLHeap, textures: [MTLTexture]) -> [MTLTexture] {
    let queue = device.makeCommandQueue()!
    let buffer = queue.makeCommandBuffer()!
    let blit = buffer.makeBlitCommandEncoder()!

    var heapTextures = [MTLTexture]()

    for texture in textures {
      let textureDescriptor = makeDescriptorFromTexture(texture)
      let heapTexture = heap.makeTexture(descriptor: textureDescriptor)!
      let region = MTLRegionMake2D(0, 0, texture.width, texture.height)
      blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                sourceOrigin: region.origin, sourceSize: region.size,
                to: heapTexture, destinationSlice: 0, destinationLevel: 0,
                destinationOrigin: region.origin)
      blit.generateMipmaps(for: heapTexture)
      heapTextures.append(heapTexture)
    }

    blit.endEncoding()
    buffer.commit()

    return heapTextures
  }

  func copyBufferToHeap(_ buffer: MTLBuffer, heap: MTLHeap) -> MTLBuffer {
    let heapBuffer = heap.makeBuffer(length: buffer.length, options: .storageModePrivate)!

    let queue = device.makeCommandQueue()!
    let commands = queue.makeCommandBuffer()!
    let blit = commands.makeBlitCommandEncoder()!

    blit.copy(from: buffer, sourceOffset: 0, to: heapBuffer, destinationOffset: 0, size: buffer.length)

    blit.endEncoding()
    commands.commit()

    return heapBuffer
  }

  func makeDescriptorFromTexture(_ texture: MTLTexture) -> MTLTextureDescriptor {
    let descriptor = MTLTextureDescriptor()

    descriptor.textureType      = texture.textureType;
    descriptor.pixelFormat      = texture.pixelFormat;
    descriptor.width            = texture.width;
    descriptor.height           = texture.height;
    descriptor.depth            = texture.depth;
    descriptor.arrayLength      = texture.arrayLength;
    descriptor.sampleCount      = texture.sampleCount;
    descriptor.storageMode      = .private;

    let widthLevels = ceil(log2(Double(texture.width)));
    let heightLevels = ceil(log2(Double(texture.height)));

    descriptor.mipmapLevelCount = Int(max(min(widthLevels, heightLevels), 1.0));

    return descriptor;
  }

  func makeHeap() -> MTLHeap {
    let heapDescriptor = MTLHeapDescriptor()
    heapDescriptor.storageMode = .private
    heapDescriptor.size = 0

    for i in 0..<inputTextures.count {
      let textureDescriptor = makeDescriptorFromTexture(inputTextures[i])
      var sizeAndAlign = device.heapTextureSizeAndAlign(descriptor: textureDescriptor)
      sizeAndAlign.size += (sizeAndAlign.size & (sizeAndAlign.align - 1)) + sizeAndAlign.align
      heapDescriptor.size += sizeAndAlign.size
    }


    var circleSizeAndAlign = device.heapBufferSizeAndAlign(length: MemoryLayout<Circle>.size * 256, options: .storageModePrivate)
    circleSizeAndAlign.size +=  (circleSizeAndAlign.size & (circleSizeAndAlign.align - 1)) + circleSizeAndAlign.align;

    heapDescriptor.size += circleSizeAndAlign.size;

    return device.makeHeap(descriptor: heapDescriptor)!
  }

  // Generates an argument buffer containing the circle data and textures
  // Note that the argument buffer does not retain any buffers it refers to
  public func generate(count: Int = 256) -> MTLBuffer {

    // use a noise source to generate sane values for an array of circles
    let noiseSource = GKPerlinNoiseSource(frequency: 0.1, octaveCount: 2, persistence: 1, lacunarity: 0.3, seed: 05535533)
    let noise = GKNoise(noiseSource)

    var circles = [Circle]()

    for i in 0..<min(count, 256) {
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
    circleBuffer = copyBufferToHeap(circleBuffer!, heap: heap!)

    let argumentEncoder = function.makeArgumentEncoder(bufferIndex: Int(BufferIndexCircleAB.rawValue))
    let encodedLength = argumentEncoder.encodedLength
    let argumentBuffer = device.makeBuffer(length: argumentEncoder.encodedLength, options: .storageModeManaged)
    argumentEncoder.setArgumentBuffer(argumentBuffer, offset: 0)

    let startIndex = Int(ABBufferIDTextures.rawValue)
    argumentEncoder.setTextures(heapTextures, range: startIndex..<startIndex+inputTextures.count)
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
    computeEncoder.useHeap(heap!)
    
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

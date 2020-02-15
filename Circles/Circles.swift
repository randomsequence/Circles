//  Created by Johnnie Walker on 11/02/2020.

import AppKit
import CoreImage
import Metal
import MetalKit

public class CircleGenerator : NSObject {
  
  let device: MTLDevice
  let pipeline: MTLComputePipelineState!
  
  var inputTexture: MTLTexture!
  let threadgroupSize: MTLSize
  
  public init(device: MTLDevice) {
    self.device = device
    let library = device.makeDefaultLibrary()!
    let function = library.makeFunction(name: "generate_circles")!
    pipeline = try! device.makeComputePipelineState(function: function)
    
    let loader = MTKTextureLoader(device: device)
    inputTexture = try! loader.newTexture(name: "testcard", scaleFactor: 1.0, bundle: nil, options: [:])
    
    let threadExecutionWidth = pipeline.threadExecutionWidth
    threadgroupSize = MTLSizeMake(threadExecutionWidth, pipeline.maxTotalThreadsPerThreadgroup / threadExecutionWidth, 1);
  }
  
  public func generate(commands: MTLCommandBuffer, texture: MTLTexture) {
    let computeEncoder = commands.makeComputeCommandEncoder()!
            
    computeEncoder.setComputePipelineState(pipeline)
    computeEncoder.setTexture(inputTexture, index: Int(TextureIndexInput.rawValue))
    computeEncoder.setTexture(texture, index: Int(TextureIndexOutput.rawValue))
    
    let width = texture.width
    let height = texture.height
    
    let threadgroupCount = MTLSizeMake(width, height, 1)
    computeEncoder.dispatchThreads(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
    
// Non-uniform thread-group size is supported by all Mac GPUs, but if it weren't we'd calculate like this:
//    let threadgroupCount = MTLSizeMake((width + threadgroupSize.width - 1) / threadgroupSize.width,
//                                       (height + threadgroupSize.height - 1) / threadgroupSize.height,
//                                       1);
//    computeEncoder.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadgroupSize)
    
    computeEncoder.endEncoding()
  }
}

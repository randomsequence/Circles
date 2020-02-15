//  Created by Johnnie Walker on 14/02/2020.

import Metal

class Renderer : NSObject {
  
  let device: MTLDevice
  let library: MTLLibrary
  let queue: MTLCommandQueue
  let circleGenerator: CircleGenerator!
  
  let vertexBuffer: MTLBuffer
  var vertexPipeline: MTLRenderPipelineState!
  var computeTexture: MTLTexture?
  
  override init() {
    device = MTLCreateSystemDefaultDevice()!
    library = device.makeDefaultLibrary()!
    queue = device.makeCommandQueue()!
    
    circleGenerator = CircleGenerator(device: device)
    
    let vertexData: [Float] = [
      -0.8, -0.8, 0.0, 0.0, 0.0,
      -0.8,  0.8, 0.0, 0.0, 1.0,
       0.8, -0.8, 0.0, 1.0, 0.0,
       0.8,  0.8, 0.0, 1.0, 1.0,
    ]
    
    let dataSize = vertexData.count * MemoryLayout.size(ofValue: vertexData[0])
    vertexBuffer = device.makeBuffer(bytes: vertexData, length: dataSize, options: [])!
    
    let fragmentProgram = library.makeFunction(name: "basic_fragment")
    let vertexProgram = library.makeFunction(name: "basic_vertex")
    
    let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
    pipelineStateDescriptor.vertexFunction = vertexProgram
    pipelineStateDescriptor.fragmentFunction = fragmentProgram
    pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
    
    vertexPipeline = try! device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)    
  }
  
  public func render(texture: MTLTexture) {
    let commands = queue.makeCommandBuffer()!
    
    let now = CFAbsoluteTimeGetCurrent()
    
    if computeTexture == nil
      || computeTexture?.width != texture.width
      || computeTexture?.height != texture.height {
      let decriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: texture.width, height: texture.height, mipmapped: false)
      decriptor.usage = [.shaderRead, .shaderWrite]
      computeTexture = device.makeTexture(descriptor: decriptor)
    }
    
    circleGenerator.generate(commands: commands, texture: computeTexture!)
    
    let renderPassDescriptor = MTLRenderPassDescriptor()
    renderPassDescriptor.colorAttachments[0].texture = texture
    renderPassDescriptor.colorAttachments[0].loadAction = .clear
    renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
      red: 0.0,
      green: (1.0 + sin(now)) * 0.5,
      blue: fabs(cos(2.0*now)) * 0.25,
      alpha: 1.0)
    
    let renderEncoder = commands.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
    renderEncoder.setRenderPipelineState(vertexPipeline)
    renderEncoder.setFragmentTexture(computeTexture!, index: Int(TextureIndexInput.rawValue))
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: 1)
    renderEncoder.endEncoding()
    
    commands.commit()
  }
  
}

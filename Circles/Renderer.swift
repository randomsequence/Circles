//  Created by Johnnie Walker on 14/02/2020.

import Metal

class Renderer : NSObject {
  
  let device: MTLDevice
  let queue: MTLCommandQueue
  let circles: Circles!
  var circleBuffer: MTLBuffer?

  let vertexBuffer: MTLBuffer
  var vertexPipeline: MTLRenderPipelineState!
  var computeTexture: MTLTexture?

  var lock : pthread_rwlock_t
  var rendering_raw = false
  var rendering: Bool {
    get {
      pthread_rwlock_rdlock(&lock)
      let rendering = rendering_raw
      pthread_rwlock_unlock(&lock)
      return rendering
    }
    set {
      pthread_rwlock_wrlock(&lock)
      rendering_raw = newValue
      pthread_rwlock_unlock(&lock)
    }
  }

  override init() {
    device = MTLCreateSystemDefaultDevice()!
    queue = device.makeCommandQueue()!
    
    let library = device.makeDefaultLibrary()!

    circles = Circles(device: device, library: library)
    circleBuffer = circles.generate()
    
    let vertexData: [Float] = [
      -1.0, -1.0, 0.0, 0.0, 0.0,
      -1.0,  1.0, 0.0, 0.0, 1.0,
       1.0, -1.0, 0.0, 1.0, 0.0,
       1.0,  1.0, 0.0, 1.0, 1.0,
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

    lock = pthread_rwlock_t()
    pthread_rwlock_init(&lock, nil)
  }

  deinit {
    pthread_rwlock_destroy(&lock)
  }

  public func render(texture: MTLTexture) {

    guard self.rendering == false else {
      return
    }

    let commands = queue.makeCommandBuffer()!
    
    let now = CFAbsoluteTimeGetCurrent()
    
    if computeTexture == nil
      || computeTexture?.width != texture.width
      || computeTexture?.height != texture.height {
      let decriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                               width: texture.width,
                                                               height: texture.height,
                                                               mipmapped: false)
      decriptor.usage = [.shaderRead, .shaderWrite]
      computeTexture = device.makeTexture(descriptor: decriptor)
    }
    
    circles.render(commands: commands, texture: computeTexture!, circles: circleBuffer!)
    
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

    self.rendering = true

    commands.addCompletedHandler { (_) in
      self.rendering = false
    }

    commands.commit()
  }
  
}

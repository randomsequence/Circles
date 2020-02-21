//  Created by Johnnie Walker on 11/02/2020.

import Cocoa
import Metal

class ViewController: NSViewController {
  
  var link: CVDisplayLink?
  var renderer: Renderer!
  
  var metalLayer: CAMetalLayer?
  var lastFrameInfo: RenderInfo = RenderInfo(time: CFAbsoluteTimeGetCurrent(), timeDelta: 0, frameIndex: 0)
  
  deinit {
    if let link = link {
      CVDisplayLinkStop(link)
    }
  }
  
  let displayLinkOutputCallback: CVDisplayLinkOutputCallback = {(displayLink: CVDisplayLink, inNow: UnsafePointer<CVTimeStamp>, inOutputTime: UnsafePointer<CVTimeStamp>, flagsIn: CVOptionFlags, flagsOut: UnsafeMutablePointer<CVOptionFlags>, displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn in
    if let context = displayLinkContext {
      let view = Unmanaged<ViewController>.fromOpaque(context).takeUnretainedValue()
      autoreleasepool {
        view.render()
      }
    }
    return kCVReturnSuccess
  }
  
  func render() {
    let renderInfo = lastFrameInfo.relativeTo(time: CFAbsoluteTimeGetCurrent())

    if renderer.rendering == false {
      if let metalLayer = metalLayer, let drawable = metalLayer.nextDrawable() {
        renderer?.render(texture: drawable.texture, info: renderInfo)
        drawable.present()
      }
    }

    lastFrameInfo = renderInfo
  }
  
  override func viewWillAppear() {
    if let window = view.window {
      metalLayer?.contentsScale = window.backingScaleFactor
    }
    
    CVDisplayLinkCreateWithActiveCGDisplays(&link)
    CVDisplayLinkSetOutputCallback(link!, displayLinkOutputCallback, Unmanaged.passUnretained(self).toOpaque())
    CVDisplayLinkStart(link!)
  }
  
  override func viewWillDisappear() {
    if let link = link {
      CVDisplayLinkStop(link)
      self.link = nil
    }
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    
    let layer = CAMetalLayer()
    layer.pixelFormat = .bgra8Unorm
    layer.framebufferOnly = true
    layer.frame = view.bounds
    layer.needsDisplayOnBoundsChange = true
    
    let renderer = Renderer()
    layer.device = renderer.device
    self.renderer = renderer
    
    metalLayer = layer
    
    view.layer = layer
  }
  
  override func viewDidLayout() {
    super.viewDidLayout()
    
    if let metalLayer = metalLayer {
      let boundsSize = metalLayer.bounds.size
      let scale = metalLayer.contentsScale
      let drawableSize = CGSize(width: boundsSize.width * scale, height: boundsSize.height * scale)
      
      if (!metalLayer.drawableSize.equalTo(drawableSize)) {
        metalLayer.drawableSize = drawableSize;
      }
    }
  }
  
  @IBAction public func increase(_ sender: Any?) {
    let count = renderer.circles.circleCount
    renderer.circles.circleCount = min(count+1, 512)
  }
  
  @IBAction public func decrease(_ sender: Any?) {
    let count = renderer.circles.circleCount
    renderer.circles.circleCount = max(count-1, 0)
    }
}


//  Created by Johnnie Walker on 11/02/2020.

import Cocoa
import Metal

class ViewController: NSViewController {
  
  var link: CVDisplayLink?
  var renderer: Renderer?
  
  var metalLayer: CAMetalLayer?
  
  deinit {
    if let link = link {
      CVDisplayLinkStop(link)
    }
  }
  
  let displayLinkOutputCallback: CVDisplayLinkOutputCallback = {(displayLink: CVDisplayLink, inNow: UnsafePointer<CVTimeStamp>, inOutputTime: UnsafePointer<CVTimeStamp>, flagsIn: CVOptionFlags, flagsOut: UnsafeMutablePointer<CVOptionFlags>, displayLinkContext: UnsafeMutableRawPointer?) -> CVReturn in
    let view = unsafeBitCast(displayLinkContext, to: ViewController.self)
    view.render()    
    return kCVReturnSuccess
  }
  
  func render() {
    if let drawable = metalLayer?.nextDrawable() {
      renderer?.render(texture: drawable.texture)
      drawable.present()
    }
  }
  
  override func viewWillAppear() {
    if let window = view.window {
      metalLayer?.contentsScale = window.backingScaleFactor
    }
    
    CVDisplayLinkCreateWithActiveCGDisplays(&link)
    CVDisplayLinkSetOutputCallback(link!, displayLinkOutputCallback, UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()))
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
    
    let renderer = Renderer()
    layer.device = renderer.device
    self.renderer = renderer
    
    metalLayer = layer
    
    view.layer = layer
  }
}

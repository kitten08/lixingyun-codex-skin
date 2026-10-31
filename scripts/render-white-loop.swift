import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage

let root = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let source = NSImage(contentsOf:root.appendingPathComponent("originals/white-art.png"))!
var proposed = CGRect(origin:.zero,size:source.size)
let art = source.cgImage(forProposedRect:&proposed,context:nil,hints:nil)!
let W = 1920, H = 1080, fps = 30, seconds = 8
let stillMode = CommandLine.arguments.contains("--no-wind")
let paper = NSColor.white
let ink = NSColor(calibratedRed:0.07,green:0.075,blue:0.08,alpha:1)
let red = NSColor(calibratedRed:0.64,green:0.14,blue:0.17,alpha:1)
func clamp(_ v:Double)->Double { min(1,max(0,v)) }
func smooth(_ x:Double)->Double { let v=clamp(x); return v*v*(3-2*v) }
func step(_ a:Double,_ b:Double,_ x:Double)->Double { smooth((x-a)/(b-a)) }
let frameRect=CGRect(x:0,y:0,width:1920,height:1080)
let ciContext=CIContext(options:[.useSoftwareRenderer:false,.cacheIntermediates:false])
let ciArt=CIImage(cgImage:art).transformed(by:CGAffineTransform(scaleX:1920/Double(art.width),y:1080/Double(art.height))).clampedToExtent()
let windKernel=CIWarpKernel(source:"""
kernel vec2 wind(float time, float strength) {
 vec2 p=destCoord();
 float phase=time*0.7853981634;
 float head=1.0-smoothstep(0.76,1.10,length((p-vec2(1280.0,850.0))/vec2(365.0,390.0)));
 float body=1.0-smoothstep(0.75,1.10,length((p-vec2(1280.0,225.0))/vec2(710.0,565.0)));
 float bg=1.0-max(head,body);
 float trail=smoothstep(1350.0,1860.0,p.x)*smoothstep(570.0,680.0,p.y)*(1.0-smoothstep(990.0,1080.0,p.y));
 float crown=smoothstep(800.0,960.0,p.y)*smoothstep(830.0,1000.0,p.x)*(1.0-smoothstep(1520.0,1650.0,p.x));
 float wisp=(1.0-smoothstep(1100.0,1240.0,p.x))*smoothstep(800.0,990.0,p.y)*smoothstep(800.0,1000.0,p.x);
 float face=1.0-smoothstep(0.72,1.1,length((p-vec2(1280.0,710.0))/vec2(150.0,210.0)));
 float dx=bg*(12.0*sin(phase+p.y*0.009)+4.0*sin(2.0*phase+p.x*0.006));
 float dy=bg*(6.0*cos(phase+p.x*0.007));
 dx+=trail*7.0*sin(2.0*phase+p.x*0.005)+crown*3.6*sin(2.0*phase+p.y*0.007)+wisp*5.0*cos(2.0*phase+p.y*0.01);
 dy+=trail*25.0*sin(2.0*phase+p.x*0.006+p.y*0.004)+crown*2.3*cos(2.0*phase+p.x*0.008)+wisp*7.0*sin(2.0*phase+p.y*0.012);
 return p+vec2(dx,dy)*strength*(1.0-face);
}
""")!
func displacement(_ p:CGPoint,_ time:Double,_ strength:Double)->CGPoint {
 let x=Double(p.x),y=Double(p.y),phase=time*Double.pi/4
 let head=1-step(0.76,1.10,hypot((x-1280)/365,(y-850)/390))
 let body=1-step(0.75,1.10,hypot((x-1280)/710,(y-225)/565))
 let bg=1-max(head,body)
 let trail=step(1350,1860,x)*step(570,680,y)*(1-step(990,1080,y))
 let crown=step(800,960,y)*step(830,1000,x)*(1-step(1520,1650,x))
 let wisp=(1-step(1100,1240,x))*step(800,990,y)*step(800,1000,x)
 let face=1-step(0.72,1.1,hypot((x-1280)/150,(y-710)/210))
 var dx=bg*(12*sin(phase+y*0.009)+4*sin(2*phase+x*0.006))
 var dy=bg*6*cos(phase+x*0.007)
 dx += trail*7*sin(2*phase+x*0.005)+crown*3.6*sin(2*phase+y*0.007)+wisp*5*cos(2*phase+y*0.01)
 dy += trail*25*sin(2*phase+x*0.006+y*0.004)+crown*2.3*cos(2*phase+x*0.008)+wisp*7*sin(2*phase+y*0.012)
 return CGPoint(x:dx*strength*(1-face),y:dy*strength*(1-face))
}
func movingArt(_ t:Double,_ strength:Double)->CGImage {
 let output=windKernel.apply(extent:frameRect,roiCallback:{ _,rect in rect.insetBy(dx:-55,dy:-55) },image:ciArt,arguments:[t,strength])!
 return ciContext.createCGImage(output,from:frameRect,format:.RGBA8,colorSpace:CGColorSpaceCreateDeviceRGB())!
}
func atmosphere(_ c:CGContext,_ t:Double,_ alpha:Double) {
 let phase=t*Double.pi/4
 // Soft clouds drift independently of the character, mainly through the left negative space.
 for i in 0..<5 {
  let v=Double(i),cx=100+v*115+100*sin(phase+v*1.2),cy=80+v*110+45*cos(phase+v*1.7)
  c.saveGState(); c.translateBy(x:cx,y:cy); c.scaleBy(x:3.4,y:0.65)
  let opacity=(0.045+0.018*sin(phase+v))*alpha
  let colors=[paper.withAlphaComponent(opacity).cgColor,paper.withAlphaComponent(opacity*0.35).cgColor,paper.withAlphaComponent(0).cgColor] as CFArray
  let g=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:colors,locations:[0,0.38,1])!
  c.drawRadialGradient(g,startCenter:.zero,startRadius:0,endCenter:CGPoint(x:20*sin(phase+v),y:7*cos(phase+v)),endRadius:205,options:[])
  c.restoreGState()
 }
 for i in 0..<90 {
  let v=Double(i),bx=(v*137.7).truncatingRemainder(dividingBy:1920),by=(v*93.8).truncatingRemainder(dividingBy:1080)
  let x=bx+75*sin(phase+v),y=by+35*cos(phase+v*0.31)
  let r=0.75+v.truncatingRemainder(dividingBy:3)*0.4
  let color=i%11 == 0 ? red : ink
  c.setFillColor(color.withAlphaComponent((0.12+0.14*(0.5+0.5*sin(phase+v)))*alpha).cgColor)
  c.fillEllipse(in:CGRect(x:x,y:y,width:r*2,height:r))
 }
}

// Extract thin, connected contours once, so both passes share exact geometry.
let ew=960, eh=540
let raster = CGContext(data:nil,width:ew,height:eh,bitsPerComponent:8,bytesPerRow:ew*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
raster.interpolationQuality = .high
raster.draw(art,in:CGRect(x:0,y:0,width:ew,height:eh))
let rep = NSBitmapImageRep(cgImage:raster.makeImage()!)
let data = rep.bitmapData!, channels = rep.samplesPerPixel, stride = rep.bytesPerRow
var gray = [Double](repeating:0,count:ew*eh)
for y in 0..<eh { for x in 0..<ew { let i=y*stride+x*channels; gray[y*ew+x]=0.2126*Double(data[i])+0.7152*Double(data[i+1])+0.0722*Double(data[i+2]) } }
let kernel=[1.0,4,6,4,1]
var horizontal=gray, blurred=gray
for y in 0..<eh { for x in 2..<(ew-2) { var s=0.0; for k in -2...2 { s += gray[y*ew+x+k]*kernel[k+2] }; horizontal[y*ew+x]=s/16 } }
for y in 2..<(eh-2) { for x in 0..<ew { var s=0.0; for k in -2...2 { s += horizontal[(y+k)*ew+x]*kernel[k+2] }; blurred[y*ew+x]=s/16 } }
var magnitude=gray, direction=[Int](repeating:0,count:ew*eh)
for y in 2..<(eh-2) { for x in 2..<(ew-2) {
 let i=y*ew+x
 let gx = -blurred[i-ew-1]+blurred[i-ew+1]-2*blurred[i-1]+2*blurred[i+1]-blurred[i+ew-1]+blurred[i+ew+1]
 let gy = -blurred[i-ew-1]-2*blurred[i-ew]-blurred[i-ew+1]+blurred[i+ew-1]+2*blurred[i+ew]+blurred[i+ew+1]
 magnitude[i]=hypot(gx,gy)/4
 let angle=(atan2(gy,gx)*180/Double.pi+180).truncatingRemainder(dividingBy:180)
 direction[i] = angle<22.5 || angle>=157.5 ? 0 : angle<67.5 ? 1 : angle<112.5 ? 2 : 3
} }
var thin=[Double](repeating:0,count:ew*eh)
for y in 3..<(eh-3) { for x in 3..<(ew-3) {
 let i=y*ew+x
 let cutoff=445.0-max(0,Double(y)-245)*0.62
 if Double(x)<cutoff { continue }
 let d=[1,ew+1,ew,ew-1][direction[i]]
 if magnitude[i]>=magnitude[i-d] && magnitude[i]>=magnitude[i+d] { thin[i]=magnitude[i] }
} }
let offsets=[-ew-1,-ew,-ew+1,-1,1,ew-1,ew,ew+1]
var edges=[Bool](repeating:false,count:ew*eh), queue=[Int]()
for i in thin.indices {
 let x=i%ew,y=i/ew
 let face = x>560 && x<720 && y>110 && y<250
 if thin[i]>(face ? 7.0 : 27.0) { edges[i]=true; queue.append(i) }
}
var qi=0
while qi<queue.count { let i=queue[qi]; qi += 1; for d in offsets { let n=i+d; let x=n%ew,y=n/ew; let face=x>560 && x<720 && y>110 && y<250; if n>ew && n<ew*(eh-1) && !edges[n] && thin[n]>(face ? 2.5 : 10) { edges[n]=true; queue.append(n) } } }
struct Stroke { let points:[CGPoint]; let lengths:[Double]; let length:Double; let start:Double; let duration:Double }
var visited=[Bool](repeating:false,count:ew*eh), strokes=[Stroke]()
let ordered=queue.sorted { a,b in
 let da=offsets.filter { edges[a+$0] }.count, db=offsets.filter { edges[b+$0] }.count
 return (da == 1 && db != 1) || ((da == 1) == (db == 1) && a<b)
}
for seed in ordered where !visited[seed] {
 var points=[CGPoint](), at=seed, previous:Int?=nil
 while !visited[at] {
  visited[at]=true
  points.append(CGPoint(x:Double(at%ew)*2,y:Double(eh-1-at/ew)*2))
  let candidates=offsets.map { at+$0 }.filter { $0>ew && $0<ew*(eh-1) && edges[$0] && !visited[$0] }
  if candidates.isEmpty { break }
  let prior=previous, current=at
  let next=candidates.max { a,b in
   guard let p=prior else { return thin[a]<thin[b] }
   let dx=Double(current%ew-p%ew),dy=Double(current/ew-p/ew)
   let sa=dx*Double(a%ew-current%ew)+dy*Double(a/ew-current/ew)
   let sb=dx*Double(b%ew-current%ew)+dy*Double(b/ew-current/ew)
   return sa<sb
  }!
  previous=at; at=next
 }
 if points.count<20 { continue }
 // Preserve an edge's shape while avoiding excessive tiny segments.
 points=points.enumerated().filter { $0.offset%2 == 0 || $0.offset == points.count-1 }.map(\.element)
 var lengths=[0.0]
 for j in 1..<points.count { lengths.append(lengths.last!+hypot(points[j].x-points[j-1].x,points[j].y-points[j-1].y)) }
 let top=points.map(\.y).max()!
 let start=0.17+1.35*(1-Double(top)/1080)+Double(strokes.count%13)*0.028
 strokes.append(Stroke(points:points,lengths:lengths,length:lengths.last!,start:start,duration:0.44+min(0.68,lengths.last!/1100)))
}
print("Connected contour strokes: \(strokes.count)")
func pathPart(_ stroke:Stroke,_ p:Double,_ t:Double,_ wind:Double)->CGPath {
 func moved(_ point:CGPoint)->CGPoint { let d=displacement(point,t,wind); return CGPoint(x:point.x-d.x,y:point.y-d.y) }
 let path=CGMutablePath(); path.move(to:moved(stroke.points[0])); let length=stroke.length*clamp(p)
 for i in 1..<stroke.points.count {
  if stroke.lengths[i]<=length { path.addLine(to:moved(stroke.points[i])); continue }
  let a=stroke.points[i-1],b=stroke.points[i]
  let q=(length-stroke.lengths[i-1])/(stroke.lengths[i]-stroke.lengths[i-1])
  path.addLine(to:moved(CGPoint(x:a.x+(b.x-a.x)*q,y:a.y+(b.y-a.y)*q))); break
 }
 return path
}
func revealMask(_ p:Double)->CGImage {
 let mw=480,mh=270
 var bytes=[UInt8](repeating:0,count:mw*mh)
 for y in 0..<mh { for x in 0..<mw {
  let dx=(Double(x)/Double(mw)-0.68)*1.3,dy=Double(y)/Double(mh)-0.29
  let distance=hypot(dx,dy)
  bytes[y*mw+x]=UInt8(255*smooth((p*1.5-distance)/0.19))
 } }
 let provider=CGDataProvider(data:Data(bytes) as CFData)!
 return CGImage(width:mw,height:mh,bitsPerComponent:8,bitsPerPixel:8,bytesPerRow:mw,space:CGColorSpaceCreateDeviceGray(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)!
}
func label(_ string:String,_ x:CGFloat,_ y:CGFloat,_ size:CGFloat,_ a:Double,_ font:String="HelveticaNeue-Light",_ tracking:CGFloat=0) {
 let baseFont=NSFont(name:font,size:size) ?? NSFont.systemFont(ofSize:size)
 let displayFont=size>=100 ? NSFontManager.shared.convert(baseFont,toHaveTrait:.boldFontMask) : baseFont
 let attrs:[NSAttributedString.Key:Any]=[.font:displayFont,.foregroundColor:ink.withAlphaComponent(a),.kern:tracking]
 NSAttributedString(string:string,attributes:attrs).draw(at:CGPoint(x:x,y:y))
}
func draw(_ c:CGContext,width:Int,height:Int,t:Double,wallpaper:Bool=false,loop:Bool=false) {
 c.saveGState(); c.scaleBy(x:Double(width)/1920,y:Double(height)/1080)
 c.setFillColor(paper.cgColor); c.fill(CGRect(x:0,y:0,width:1920,height:1080))
 if wallpaper { c.draw(art,in:CGRect(x:0,y:0,width:1920,height:1080)); c.restoreGState(); return }
 let wind=stillMode ? 0.0 : (loop ? 1.0 : smooth((t-2.9)/1.4))
 
 c.saveGState()
 let zoom=(stillMode || loop) ? 1.0 : 1.028-0.028*smooth(t/6.4)
 c.translateBy(x:1310,y:620); c.scaleBy(x:zoom,y:zoom); c.translateBy(x:-1310,y:-620)
 let fill=loop ? 1.0 : smooth((t-2.95)/1.38)
 if fill>0 {
  c.saveGState()
  if fill<0.999 { c.clip(to:CGRect(x:0,y:0,width:1920,height:1080),mask:revealMask(fill)) }
  c.draw(movingArt(t,wind),in:CGRect(x:0,y:0,width:1920,height:1080)); c.restoreGState()
 }
 let lineAlpha=loop ? 0.0 : 1-smooth((t-3.05)/1.4)
 if lineAlpha>0 {
  c.setLineCap(.round); c.setLineJoin(.round)
  for (i,s) in strokes.enumerated() {
   let p=clamp((t-s.start)/s.duration); if p<=0 { continue }
   let path=pathPart(s,p,t,wind), color=i%17 == 0 ? red : ink
   c.setStrokeColor(color.withAlphaComponent(0.025*lineAlpha).cgColor); c.setLineWidth(3.8); c.addPath(path); c.strokePath()
   c.setShadow(offset:.zero,blur:1.2,color:color.withAlphaComponent(0.17*lineAlpha).cgColor)
   c.setStrokeColor(color.withAlphaComponent(0.98*lineAlpha).cgColor); c.setLineWidth(1.5); c.addPath(path); c.strokePath()
   c.setShadow(offset:.zero,blur:0,color:nil)
   if p<1 { let end=path.currentPoint; c.setFillColor(color.withAlphaComponent(0.88*lineAlpha).cgColor); c.fillEllipse(in:CGRect(x:end.x-1.3,y:end.y-1.3,width:2.6,height:2.6)) }
  }
 }
 c.restoreGState()
 if !stillMode { atmosphere(c,t,loop ? 1.0 : smooth((t-2.95)/1.4)) }
 // A continuous white wash keeps the type legible over the ink landscape.
 let textTime=loop ? 5.0 : t
 let washAlpha=loop ? 1.0 : smooth((t-2.95)/1.4)
 let washColors=[paper.withAlphaComponent(0.76*washAlpha).cgColor,paper.withAlphaComponent(0.46*washAlpha).cgColor,paper.withAlphaComponent(0).cgColor] as CFArray
 let wash=CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:washColors,locations:[0,0.62,1])!
 c.drawLinearGradient(wash,start:CGPoint(x:0,y:540),end:CGPoint(x:810,y:540),options:[])
 NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current=NSGraphicsContext(cgContext:c,flipped:false)
 let a=smooth((textTime-2.85)/0.95), slide=12*(1-a)
 label("CODEX",128,768+slide,29,a*0.68,"HelveticaNeue-Light",8)
 for (i,ch) in Array("你欲何为").enumerated() {
  let qa=smooth((textTime-3.2-Double(i)*0.11)/0.8)
  label(String(ch),120+CGFloat(i)*121,610+10*(1-qa),108,qa,"Songti SC",0)
 }
 label("李星云",128,530+slide,27,a*0.86,"Songti SC",10)
 label("画江湖之不良人",129,487+slide,15,a*0.56,"Songti SC",4)
 c.setFillColor(red.withAlphaComponent(a*0.9).cgColor); c.fill(CGRect(x:128,y:581,width:64*smooth((textTime-3.7)/0.6),height:2))
 NSGraphicsContext.restoreGraphicsState()
 let end=(stillMode || loop) ? 0.0 : smooth((t-7.55)/0.45)
 c.setFillColor(paper.withAlphaComponent(end).cgColor); c.fill(CGRect(x:0,y:0,width:1920,height:1080))
 c.restoreGState()
}
func bitmap(_ w:Int,_ h:Int,_ t:Double,_ wallpaper:Bool=false,_ loop:Bool=false)->CGImage {
 let c=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 draw(c,width:w,height:h,t:t,wallpaper:wallpaper,loop:loop); return c.makeImage()!
}
func save(_ image:CGImage,_ url:URL) {
 let d=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil)!
 CGImageDestinationAddImage(d,image,nil); precondition(CGImageDestinationFinalize(d))
}
if !CommandLine.arguments.contains("--gif-only") {
let loopMode=CommandLine.arguments.contains("--loop")
let url=root.appendingPathComponent("media/white-wind-loop.mp4")
let writer=try AVAssetWriter(outputURL:url,fileType:.mp4)
let settings:[String:Any]=[AVVideoCodecKey:AVVideoCodecType.h264,AVVideoWidthKey:W,AVVideoHeightKey:H,AVVideoCompressionPropertiesKey:[AVVideoAverageBitRateKey:10_000_000,AVVideoProfileLevelKey:AVVideoProfileLevelH264HighAutoLevel]]
let input=AVAssetWriterInput(mediaType:.video,outputSettings:settings)
let adaptor=AVAssetWriterInputPixelBufferAdaptor(assetWriterInput:input,sourcePixelBufferAttributes:[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32ARGB,kCVPixelBufferWidthKey as String:W,kCVPixelBufferHeightKey as String:H,kCVPixelBufferCGImageCompatibilityKey as String:true,kCVPixelBufferCGBitmapContextCompatibilityKey as String:true])
writer.add(input); guard writer.startWriting() else { print(writer.error!); exit(1) }; writer.startSession(atSourceTime:.zero)
for frame in 0..<(fps*seconds) {
 while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval:0.004) }
 autoreleasepool {
  var pb:CVPixelBuffer?; precondition(CVPixelBufferPoolCreatePixelBuffer(nil,adaptor.pixelBufferPool!,&pb)==kCVReturnSuccess)
  CVPixelBufferLockBaseAddress(pb!,[])
  let c=CGContext(data:CVPixelBufferGetBaseAddress(pb!),width:W,height:H,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pb!),space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipFirst.rawValue)!
  draw(c,width:W,height:H,t:Double(frame)/Double(fps),loop:loopMode); CVPixelBufferUnlockBaseAddress(pb!,[])
  precondition(adaptor.append(pb!,withPresentationTime:CMTime(value:Int64(frame),timescale:Int32(fps))))
 }
 if frame%30==0 { print("Rendered \(frame)/240") }
}
input.markAsFinished(); let done=DispatchSemaphore(value:0); writer.finishWriting { done.signal() }; done.wait()
precondition(writer.status == .completed,"\(String(describing:writer.error))")
if loopMode { print("Loop export complete"); exit(0) }
}

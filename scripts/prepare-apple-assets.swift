#!/usr/bin/env swift
import AppKit
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = root.appendingPathComponent("assets/generated/appicon/Yeti3-AppIcon-1024.png")
guard let image = NSImage(contentsOf: source) else { fatalError("Missing master icon") }
func export(_ size: Int, to path: String, opaque: Bool) throws {
    guard let cgSource = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size*4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue) else { fatalError("Bitmap context") }
    if opaque { context.setFillColor(CGColor(red:0.025,green:0.055,blue:0.08,alpha:1)); context.fill(CGRect(x:0,y:0,width:size,height:size)) }
    context.interpolationQuality = .high
    context.draw(cgSource, in: CGRect(x:0,y:0,width:size,height:size))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    var lo = 255, hi = 0
    for y in stride(from:0,to:size,by:max(1,size/64)) { for x in stride(from:0,to:size,by:max(1,size/64)) { for c in 0..<3 { let v=Int(bytes[(y*size+x)*4+c]);lo=min(lo,v);hi=max(hi,v) } } }
    guard hi-lo > 80 else { fatalError("Blank/flat icon: \(path)") }
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let output=context.makeImage(),let destination=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else { fatalError("PNG destination") }
    CGImageDestinationAddImage(destination,output,nil)
    guard CGImageDestinationFinalize(destination) else {fatalError("PNG export")}
    print("Verified \(size)x\(size): \(path)")
}
try export(1024,to:"ios/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png",opaque:true)
try export(1024,to:"ios/Release/StoreAssets/icons/iOS-AppIcon-1024.png",opaque:true)
for size in [16,32,128,256,512] { for scale in [1,2] { try export(size*scale,to:"ios/Release/StoreAssets/icons/macOS.iconset/icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png",opaque:false) } }
let manifestURL = root.appendingPathComponent("ios/Release/StoreAssets/manifest.json")
var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String:Any]
let assetsRoot = manifestURL.deletingLastPathComponent()
var files = [[String:Any]]()
for case let url as URL in FileManager.default.enumerator(at:assetsRoot,includingPropertiesForKeys:nil)! where ["png","icns"].contains(url.pathExtension) {
 let data = try Data(contentsOf:url)
 var record:[String:Any] = ["path":String(url.path.dropFirst(assetsRoot.path.count+1)),"sha256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()]
 if let bitmap=NSBitmapImageRep(data:data) {record["width"]=bitmap.pixelsWide;record["height"]=bitmap.pixelsHigh}
 files.append(record)
}
manifest["files"]=files.sorted{($0["path"] as! String)<($1["path"] as! String)}
try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]).write(to:manifestURL)

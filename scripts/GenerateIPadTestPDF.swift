import AppKit

import Foundation
import CoreGraphics
import CoreText
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let pageCount = Int(CommandLine.arguments.dropFirst(2).first ?? "90") ?? 90
var box = CGRect(x: 0, y: 0, width: 960, height: 720)
let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
for n in 1...pageCount {
 ctx.beginPDFPage(nil)
 ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(box)
 let lines = ["Working capital and invested capital", "Source slide \(n) · Finance lecture", "Assets", "Property, plant and equipment", "Inventories and trade receivables", "NWC = Operating Current Assets – Operating Current Liabilities"]
 for (i, text) in lines.enumerated() {
  let attrs: [NSAttributedString.Key: Any] = [.font: CTFontCreateWithName("Helvetica" as CFString, i == 0 ? 28 : 18, nil), .foregroundColor: CGColor(red: 0.08, green: 0.25, blue: 0.55, alpha: 1)]
  let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
  ctx.textPosition = CGPoint(x: 48, y: 640 - i * 60); CTLineDraw(line, ctx)
 }
 ctx.endPDFPage()
}
ctx.closePDF()

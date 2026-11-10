// SPDX-License-Identifier: GPL-3.0-or-later
// Batch PDF helper for media_inject.py (PDFKit, local only).
// stdin lines:  <src.pdf>\t<dst.thumb>\t<max_side>
// stdout lines: <src.pdf>\t<page_count>\t<ok|fail>
// Writes a JPEG of page 1 scaled so its longer side is <max_side> px (like WhatsApp's .thumb files).
import AppKit
import PDFKit

while let line = readLine() {
    let parts = line.components(separatedBy: "\t")
    guard parts.count == 3, let maxSide = Double(parts[2]) else { print("\(line)\t0\tfail"); continue }
    let src = URL(fileURLWithPath: parts[0]), dst = URL(fileURLWithPath: parts[1])
    guard let doc = PDFDocument(url: src), let page = doc.page(at: 0) else { print("\(parts[0])\t0\tfail"); continue }
    let box = page.bounds(for: .mediaBox)
    let scale = maxSide / max(box.width, box.height, 1)
    let size = NSSize(width: max(1, (box.width * scale).rounded()), height: max(1, (box.height * scale).rounded()))
    let img = page.thumbnail(of: size, for: .mediaBox)
    var ok = "fail"
    if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
       let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) {
        ok = ((try? jpg.write(to: dst)) != nil) ? "ok" : "fail"
    }
    print("\(parts[0])\t\(doc.pageCount)\t\(ok)")
    fflush(stdout)
}

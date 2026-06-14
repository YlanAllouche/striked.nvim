import AppKit
import Foundation

struct Payload: Decodable {
    let text: String?
    let html: String
    let html_only: Bool?
}

let data = FileHandle.standardInput.readDataToEndOfFile()
let payload = try JSONDecoder().decode(Payload.self, from: data)
let pasteboard = NSPasteboard.general

pasteboard.clearContents()

if payload.html_only != true {
    pasteboard.setString(payload.text ?? "", forType: .string)
}

pasteboard.setString(payload.html, forType: .html)

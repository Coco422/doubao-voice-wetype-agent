import Carbon
import Foundation

func getID(_ source: TISInputSource) -> String? {
    guard let raw = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return unsafeBitCast(raw, to: CFString.self) as String
}

let args = CommandLine.arguments
let target = args.count > 1 ? args[1] : "--current"

if target == "--current" {
    if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
       let id = getID(current) {
        print(id)
        exit(0)
    }
    if let current = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
       let id = getID(current) {
        print(id)
        exit(0)
    }
    fputs("No current input source\n", stderr)
    exit(2)
}

if target == "--list" {
    let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
    for item in list {
        let src = item as! TISInputSource
        if let id = getID(src) { print(id) }
    }
    exit(0)
}

let properties = [kTISPropertyInputSourceID: target] as CFDictionary
let list = TISCreateInputSourceList(properties, false).takeRetainedValue() as NSArray
if list.count == 0 {
    fputs("Input source not found: \(target)\n", stderr)
    exit(1)
}

let source = list[0] as! TISInputSource
let status = TISSelectInputSource(source)
if status != noErr {
    fputs("TISSelectInputSource failed: \(status)\n", stderr)
    exit(1)
}
print(target)

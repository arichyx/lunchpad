import Foundation
import MultitouchKit
import Darwin

// Flush high-frequency probe output immediately instead of waiting for stdout buffering.
setbuf(stdout, nil)

let monitor = MultitouchMonitor(fingerCount: 4)
var lastContactCount = -1
var lastRecordCount = -1
var lastPrintTime = 0.0
var maximumFourFingerDistance: Double?

monitor.onFrame = { frame in
    let contacts = frame.activeContacts
    let now = ProcessInfo.processInfo.systemUptime

    // Show both report records and active contacts to diagnose state filtering.
    guard frame.contacts.count != lastRecordCount
            || contacts.count != lastContactCount
            || now - lastPrintTime >= 0.1 else {
        return
    }
    lastRecordCount = frame.contacts.count
    lastContactCount = contacts.count
    lastPrintTime = now

    var pinchDetail = ""
    if contacts.count == 4 {
        let distance = meanPairwiseDistance(contacts)
        maximumFourFingerDistance = max(maximumFourFingerDistance ?? distance, distance)
        if let maximumFourFingerDistance {
            pinchDetail = " spread=\(String(format: "%.3f", distance)) ratio=\(String(format: "%.3f", distance / maximumFourFingerDistance))"
        }
    } else {
        maximumFourFingerDistance = nil
    }

    let detail = frame.contacts.map { contact in
        let marker = contact.isActive ? "active" : "inactive"
        return "#\(contact.identifier){state=\(contact.state), \(marker), x=\(String(format: "%.3f", contact.x)), y=\(String(format: "%.3f", contact.y))}"
    }.joined(separator: " ")
    print("[MT] records=\(frame.contacts.count) active=\(contacts.count)\(pinchDetail) \(detail)")
}

monitor.onPinch = {
    print("🚀 Detected four-finger inward pinch")
}

monitor.onError = { error in
    print("❌ \(error)")
}

func meanPairwiseDistance(_ contacts: [MultitouchContact]) -> Double {
    var total = 0.0
    var count = 0
    for first in contacts.indices {
        for second in contacts.indices where second > first {
            total += hypot(
                contacts[first].x - contacts[second].x,
                contacts[first].y - contacts[second].y
            )
            count += 1
        }
    }
    return count == 0 ? 0 : total / Double(count)
}

do {
    try monitor.start()
    print("AppleMultitouchDevice stream started. Touch the trackpad; press Ctrl+C to exit.")
    RunLoop.main.run()
} catch {
    print("❌ Failed to start: \(error)")
    exit(EXIT_FAILURE)
}

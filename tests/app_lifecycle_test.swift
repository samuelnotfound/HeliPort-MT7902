// SPDX-License-Identifier: BSD-3-Clause
import Foundation

@main
struct AppLifecycleTests {
    static func waitUntil(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        precondition(condition(), "Main-run-loop work did not finish")
    }

    static func main() {
        var frames: [Int] = []
        let animation = ConnectionAnimation(interval: 0.005, frameCount: { 3 }, render: {
            precondition(Thread.isMainThread)
            frames.append($0)
        })
        animation.start()
        animation.start() // Repeated connecting status must not create/reset a second timer.
        precondition(frames == [0])
        waitUntil { frames.count >= 7 }
        precondition(Array(frames.prefix(7)) == [0,1,2,1,0,1,2])
        animation.stop()
        let stoppedCount = frames.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        precondition(!animation.isRunning && frames.count == stoppedCount)

        // The old implementation force-unwrapped a shared timer after another
        // queue could clear it. Exercise rapid connect/connected transitions.
        let submitted = DispatchGroup()
        var drained = false
        submitted.enter()
        DispatchQueue.global().async {
            for _ in 0..<200 { animation.start(); animation.stop() }
            DispatchQueue.main.async { drained = true }
            submitted.leave()
        }
        precondition(submitted.wait(timeout: .now() + 3) == .success)
        waitUntil { drained }
        precondition(!animation.isRunning)
        let finalCount = frames.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        precondition(frames.count == finalCount && frames.allSatisfy { (0..<3).contains($0) })

        let empty = ConnectionAnimation(frameCount: { 0 }, render: { _ in preconditionFailure("No frames") })
        empty.start()
        precondition(!empty.isRunning)
        var oneFrameCount = 0
        var availableFrames = 1
        let single = ConnectionAnimation(interval: 0.005, frameCount: { availableFrames }, render: {
            precondition($0 == 0)
            oneFrameCount += 1
        })
        single.start()
        waitUntil { oneFrameCount >= 3 }
        availableFrames = 0
        waitUntil { !single.isRunning }

        precondition(InterfaceDetails.firstAddress(in: nil) == nil)
        precondition(InterfaceDetails.firstAddress(in: ["Addresses": 123]) == nil)
        precondition(InterfaceDetails.firstAddress(in: ["Addresses": ["", "192.0.2.10"]]) == "192.0.2.10")
        precondition(InterfaceDetails.router(in: ["Router": "192.0.2.1"]) == "192.0.2.1")
        precondition(InterfaceDetails.router(in: ["Router": []]) == nil)
        precondition(InterfaceDetails.router(in: ["Router": ""]) == nil)
        precondition(InterfaceDetails.macAddress(bsd: "") == nil)
        precondition(InterfaceDetails.localAddress(bsd: "") == nil)
        precondition(InterfaceDetails.routerAddress(bsd: "") == nil)
        precondition(InterfaceDetails.macAddress(bsd: "mt7902-fixture-missing") == nil)
        print("Passed main-thread animation cancellation/restart and missing-interface/typed snapshot regression tests")
    }
}

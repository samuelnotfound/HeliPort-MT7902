// SPDX-License-Identifier: BSD-3-Clause
import Foundation

// One main-run-loop timer owns the animation. Driver callbacks may call start/stop
// from worker queues; no background run loop or force-unwrapped shared timer is used.
final class ConnectionAnimation {
    private let interval: TimeInterval
    private let frameCount: () -> Int
    private let render: (Int) -> Void
    private var timer: Timer?
    private var index = 0
    private var direction = 1

    init(interval: TimeInterval = 0.3, frameCount: @escaping () -> Int, render: @escaping (Int) -> Void) {
        self.interval = interval
        self.frameCount = frameCount
        self.render = render
    }

    var isRunning: Bool { timer != nil } // Read only on the main thread.

    func start() {
        onMain { [weak self] in
            guard let self, self.timer == nil, self.frameCount() > 0 else { return }
            self.index = 0
            self.direction = 1
            let timer = Timer(timeInterval: self.interval, repeats: true) { [weak self] timer in
                guard let self, self.timer === timer else { return }
                self.tick()
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            self.tick()
        }
    }

    func stop() {
        onMain { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    private func tick() {
        let count = frameCount()
        guard count > 0 else { stop(); return }
        if index < 0 || index >= count { index = 0; direction = 1 }
        render(index)
        guard count > 1 else { return }
        if index == count - 1 { direction = -1 }
        else if index == 0 { direction = 1 }
        index += direction
    }

    private func onMain(_ body: @escaping () -> Void) {
        if Thread.isMainThread { body() }
        else { DispatchQueue.main.async(execute: body) }
    }

    deinit { timer?.invalidate() }
}

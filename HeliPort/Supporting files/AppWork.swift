// SPDX-License-Identifier: BSD-3-Clause
import Foundation

// A menu may open and close many times. Keep one timer on the main run loop,
// including its event-tracking mode; never create a worker run loop per click.
final class MainRunLoopTimer {
    private var timer: Timer?
    var isRunning: Bool { timer != nil } // Read on main.

    func start(interval: TimeInterval, immediately: Bool = false, action: @escaping () -> Void) {
        onMain { [weak self] in
            guard let self, self.timer == nil else { return }
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
                guard let self, self.timer === timer else { return }
                action()
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
            if immediately { action() }
        }
    }

    func stop() {
        onMain { [weak self] in
            self?.timer?.invalidate()
            self?.timer = nil
        }
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Thread.isMainThread { action() }
        else { DispatchQueue.main.async(execute: action) }
    }

    deinit { timer?.invalidate() }
}

// Reserve work before dispatching it. Tokens prevent duplicate/late callbacks
// from releasing a newer request. No lock is held during IOKit or UI work.
final class WorkGate {
    private let lock = NSLock()
    private var active: UUID?

    var isBusy: Bool {
        lock.lock(); defer { lock.unlock() }
        return active != nil
    }

    func begin() -> UUID? {
        lock.lock(); defer { lock.unlock() }
        guard active == nil else { return nil }
        let token = UUID()
        active = token
        return token
    }

    func isCurrent(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active == token
    }

    @discardableResult func finish(_ token: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard active == token else { return false }
        active = nil
        return true
    }
}

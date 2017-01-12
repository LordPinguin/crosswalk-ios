// Copyright (c) 2014 Intel Corporation. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Foundation

open class XWalkThread : Thread {
    var timer: Timer!

    deinit {
        cancel()
    }

    override open func main() {
        repeat {
            switch  CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 60, true) {
                case CFRunLoopRunResult.finished:
                    // No input source, add a timer (which will never fire) to avoid spinning.
                    let interval = Date.distantFuture.timeIntervalSinceNow
                    timer = Timer(timeInterval: interval, target: self, selector: #selector(XWalkThread.neverCallIt), userInfo: nil, repeats: false)
                    RunLoop.current.add(timer, forMode: RunLoopMode.defaultRunLoopMode)
                case CFRunLoopRunResult.handledSource:
                    // Remove the timer because run loop has had input source
                    if timer != nil {
                        timer.invalidate()
                        timer = nil
                    }
                case CFRunLoopRunResult.stopped:
                    cancel()
                default:
                    break
            }
        } while !isCancelled
    }
    
    func neverCallIt() {
    }
}

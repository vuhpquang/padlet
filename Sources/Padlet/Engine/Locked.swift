// Engine/Locked.swift
// A value shared between the main thread (settings) and the multitouch thread (frames).

import Foundation

final class Locked<Value> {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) { _value = value }

    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}

import Foundation

/// Thin Swift binding over Apple's private IOReport framework.
///
/// IOReport is undocumented and ships inside the dyld shared cache as
/// `/usr/lib/libIOReport.dylib`. It is the same interface `powermetrics` uses,
/// but a normal user can subscribe and read from it with no root and no
/// entitlement. Every symbol we depend on is resolved here and nowhere else, so
/// if a future macOS renames or drops one, exactly one file fails, and it fails loudly.
///
/// Only read paths are used. Nothing here mutates hardware state.
enum IOReportError: Error, CustomStringConvertible {
    case dylibMissing
    case symbolMissing(String)
    case subscriptionFailed(String)

    var description: String {
        switch self {
        case .dylibMissing:
            return "could not dlopen /usr/lib/libIOReport.dylib"
        case .symbolMissing(let s):
            return "IOReport symbol not found: \(s) (macOS changed the private ABI)"
        case .subscriptionFailed(let g):
            return "IOReportCreateSubscription returned NULL for group \(g)"
        }
    }
}

/// Opaque subscription handle.
typealias IOReportSubscriptionRef = UnsafeMutableRawPointer

/// Resolves and holds the IOReport C function pointers. One instance per process.
final class IOReportSymbols {
    typealias FnCopyChannelsInGroup =
        @convention(c) (CFString?, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
    typealias FnMergeChannels =
        @convention(c) (CFMutableDictionary, CFMutableDictionary, CFTypeRef?) -> Void
    typealias FnCreateSubscription =
        @convention(c) (UnsafeMutableRawPointer?, CFMutableDictionary,
                        UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?)
        -> IOReportSubscriptionRef?
    typealias FnCreateSamples =
        @convention(c) (IOReportSubscriptionRef, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias FnCreateSamplesDelta =
        @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
    typealias FnIterate =
        @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
    typealias FnChanStr = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
    typealias FnStateCount = @convention(c) (CFDictionary) -> Int32
    typealias FnStateName = @convention(c) (CFDictionary, Int32) -> Unmanaged<CFString>?
    typealias FnStateResidency = @convention(c) (CFDictionary, Int32) -> Int64
    typealias FnSimpleValue = @convention(c) (CFDictionary, Int32) -> Int64

    let copyChannelsInGroup: FnCopyChannelsInGroup
    let mergeChannels: FnMergeChannels
    let createSubscription: FnCreateSubscription
    let createSamples: FnCreateSamples
    let createSamplesDelta: FnCreateSamplesDelta
    let iterate: FnIterate
    let getGroup: FnChanStr
    let getSubGroup: FnChanStr
    let getChannelName: FnChanStr
    let getUnitLabel: FnChanStr
    let stateCount: FnStateCount
    let stateName: FnStateName
    let stateResidency: FnStateResidency
    let simpleValue: FnSimpleValue

    private let handle: UnsafeMutableRawPointer

    static let shared: IOReportSymbols? = try? IOReportSymbols()

    init() throws {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else {
            throw IOReportError.dylibMissing
        }
        handle = h
        func sym<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let p = dlsym(h, name) else { throw IOReportError.symbolMissing(name) }
            return unsafeBitCast(p, to: T.self)
        }
        copyChannelsInGroup = try sym("IOReportCopyChannelsInGroup", FnCopyChannelsInGroup.self)
        mergeChannels       = try sym("IOReportMergeChannels", FnMergeChannels.self)
        createSubscription  = try sym("IOReportCreateSubscription", FnCreateSubscription.self)
        createSamples       = try sym("IOReportCreateSamples", FnCreateSamples.self)
        createSamplesDelta  = try sym("IOReportCreateSamplesDelta", FnCreateSamplesDelta.self)
        iterate             = try sym("IOReportIterate", FnIterate.self)
        getGroup            = try sym("IOReportChannelGetGroup", FnChanStr.self)
        getSubGroup         = try sym("IOReportChannelGetSubGroup", FnChanStr.self)
        getChannelName      = try sym("IOReportChannelGetChannelName", FnChanStr.self)
        getUnitLabel        = try sym("IOReportChannelGetUnitLabel", FnChanStr.self)
        stateCount          = try sym("IOReportStateGetCount", FnStateCount.self)
        stateName           = try sym("IOReportStateGetNameForIndex", FnStateName.self)
        stateResidency      = try sym("IOReportStateGetResidency", FnStateResidency.self)
        simpleValue         = try sym("IOReportSimpleGetIntegerValue", FnSimpleValue.self)
    }
}

/// One channel row surfaced during iteration of a sample delta.
struct IOReportChannel {
    let raw: CFDictionary
    private let sym: IOReportSymbols

    init(_ raw: CFDictionary, _ sym: IOReportSymbols) {
        self.raw = raw
        self.sym = sym
    }

    private func str(_ fn: IOReportSymbols.FnChanStr) -> String {
        guard let u = fn(raw) else { return "" }
        return u.takeUnretainedValue() as String
    }

    var group: String { str(sym.getGroup) }
    var subGroup: String { str(sym.getSubGroup) }
    var name: String { str(sym.getChannelName) }
    var unit: String { str(sym.getUnitLabel) }
    var stateCount: Int { Int(sym.stateCount(raw)) }

    func stateName(_ i: Int) -> String {
        guard let u = sym.stateName(raw, Int32(i)) else { return "" }
        return u.takeUnretainedValue() as String
    }
    func residency(_ i: Int) -> Int64 { sym.stateResidency(raw, Int32(i)) }
    var integerValue: Int64 { sym.simpleValue(raw, 0) }
}

/// A live subscription to one or more IOReport groups. Holds the previous sample
/// and yields per-interval deltas, which is what utilization and power are built on.
final class IOReportSubscription {
    private let sym: IOReportSymbols
    private let subscription: IOReportSubscriptionRef
    private let channels: CFMutableDictionary
    private var previous: CFDictionary?
    /// Wall-clock time of the previous sample, for converting energy deltas to watts.
    private(set) var previousSampleTime: Date?

    /// - Parameter groups: (group, subGroup?) pairs, e.g. ("GPU Stats", "GPU Performance States").
    init(groups: [(String, String?)]) throws {
        guard let sym = IOReportSymbols.shared else { throw IOReportError.dylibMissing }
        self.sym = sym

        var merged: CFMutableDictionary?
        for (g, sg) in groups {
            guard let dict = sym.copyChannelsInGroup(g as CFString, sg as CFString?, 0, 0, 0)?
                .takeRetainedValue() else { continue }
            if let existing = merged {
                sym.mergeChannels(existing, dict, nil)
            } else {
                merged = dict
            }
        }
        guard let desired = merged else {
            throw IOReportError.subscriptionFailed(groups.map(\.0).joined(separator: "+"))
        }

        var subbedChannels: Unmanaged<CFMutableDictionary>?
        guard let sub = sym.createSubscription(nil, desired, &subbedChannels, 0, nil) else {
            throw IOReportError.subscriptionFailed(groups.map(\.0).joined(separator: "+"))
        }
        self.subscription = sub
        // Prefer the channel set the subscription actually bound, and fall back to desired.
        self.channels = subbedChannels?.takeRetainedValue() ?? desired
    }

    /// Take a fresh sample and return the delta against the previous one.
    /// Returns nil on the very first call (no baseline yet).
    @discardableResult
    func sampleDelta(_ body: (IOReportChannel) -> Void) -> TimeInterval? {
        guard let current = sym.createSamples(subscription, channels, nil)?.takeRetainedValue() else {
            return nil
        }
        let now = Date()
        defer { previous = current; previousSampleTime = now }

        guard let prev = previous, let prevTime = previousSampleTime else { return nil }
        guard let delta = sym.createSamplesDelta(prev, current, nil)?.takeRetainedValue() else {
            return nil
        }
        let elapsed = now.timeIntervalSince(prevTime)
        let sym = self.sym
        sym.iterate(delta, { chanDict in
            body(IOReportChannel(chanDict, sym))
            return 0
        })
        return elapsed
    }
}

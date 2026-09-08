import Foundation

/// A self-contained IOReport channel lister, used only by the `--dump-ioreport`
/// diagnostic. It does its own `dlopen`/`dlsym` on purpose, so probing for new
/// channels (ANE power, memory bandwidth) can never destabilise the production
/// readers in `IOReport.swift`. Read-only.
public enum IOReportInspector {
    /// One line per available channel: `group | subgroup | channel | unit | states=N`.
    public static func dump() -> [String] {
        guard let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW) else {
            return ["could not dlopen /usr/lib/libIOReport.dylib"]
        }
        typealias FnCopyAll = @convention(c) (UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
        typealias FnIterate = @convention(c) (CFDictionary, @convention(block) (CFDictionary) -> Int32) -> Void
        typealias FnStr = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
        typealias FnCount = @convention(c) (CFDictionary) -> Int32

        func sym<T>(_ name: String, _ t: T.Type) -> T? {
            guard let p = dlsym(h, name) else { return nil }
            return unsafeBitCast(p, to: T.self)
        }
        guard let copyAll = sym("IOReportCopyAllChannels", FnCopyAll.self),
              let iterate = sym("IOReportIterate", FnIterate.self),
              let getGroup = sym("IOReportChannelGetGroup", FnStr.self),
              let getSub = sym("IOReportChannelGetSubGroup", FnStr.self),
              let getName = sym("IOReportChannelGetChannelName", FnStr.self),
              let getUnit = sym("IOReportChannelGetUnitLabel", FnStr.self),
              let stateCount = sym("IOReportStateGetCount", FnCount.self)
        else {
            return ["IOReportCopyAllChannels or an accessor symbol is missing on this macOS"]
        }
        guard let all = copyAll(0, 0)?.takeRetainedValue() else {
            return ["IOReportCopyAllChannels returned NULL"]
        }

        func s(_ fn: FnStr, _ d: CFDictionary) -> String { fn(d)?.takeUnretainedValue() as String? ?? "" }
        var lines: [String] = []
        iterate(all, { chan in
            let g = s(getGroup, chan), sg = s(getSub, chan), n = s(getName, chan), u = s(getUnit, chan)
            let states = Int(stateCount(chan))
            lines.append("\(g) | \(sg) | \(n) | \(u) | states=\(states)")
            return 0
        })
        return lines.sorted()
    }
}

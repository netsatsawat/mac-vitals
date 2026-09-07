import Foundation
import IOKit

/// Disk read/write throughput from the IOKit block-storage drivers, plus free and
/// total space from `statfs` on the boot volume. The drivers keep cumulative byte
/// counters, so throughput is the diff since the previous read over elapsed time.
final class DiskReader {
    private var previousRead: UInt64 = 0
    private var previousWrite: UInt64 = 0
    private var previousTime: Date?

    private func cumulative() -> (read: UInt64, write: UInt64) {
        var iterator = io_iterator_t()
        let match = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, match, &iterator) == KERN_SUCCESS else {
            return (0, 0)
        }
        defer { IOObjectRelease(iterator) }

        var read: UInt64 = 0, write: UInt64 = 0
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let props = IORegistryEntryCreateCFProperty(
                service, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] else { continue }
            if let r = props["Bytes (Read)"] as? NSNumber { read += r.uint64Value }
            if let w = props["Bytes (Write)"] as? NSNumber { write += w.uint64Value }
        }
        return (read, write)
    }

    private func capacity() -> (free: UInt64, total: UInt64) {
        var s = statfs()
        guard statfs("/", &s) == 0 else { return (0, 0) }
        let block = UInt64(s.f_bsize)
        return (UInt64(s.f_bavail) * block, UInt64(s.f_blocks) * block)
    }

    func read() -> DiskSnapshot {
        let now = Date()
        let (r, w) = cumulative()
        let (free, total) = capacity()
        defer { previousRead = r; previousWrite = w; previousTime = now }

        guard let prev = previousTime, now.timeIntervalSince(prev) > 0 else {
            return DiskSnapshot(readBytesPerSec: 0, writeBytesPerSec: 0, freeBytes: free, totalBytes: total)
        }
        let elapsed = now.timeIntervalSince(prev)
        let readRate = r >= previousRead ? Double(r - previousRead) / elapsed : 0
        let writeRate = w >= previousWrite ? Double(w - previousWrite) / elapsed : 0
        return DiskSnapshot(readBytesPerSec: readRate, writeBytesPerSec: writeRate,
                            freeBytes: free, totalBytes: total)
    }
}

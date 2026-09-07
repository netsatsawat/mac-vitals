import Foundation

/// Shared number formatting for the app's readouts.
enum Fmt {
    /// A byte rate as B/s, KB/s, or MB/s.
    static func rate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 { return String(format: "%.1f MB/s", bytesPerSec / 1_048_576) }
        if bytesPerSec >= 1024 { return String(format: "%.0f KB/s", bytesPerSec / 1024) }
        return String(format: "%.0f B/s", bytesPerSec)
    }

    /// A byte count as GB with one decimal.
    static func gb(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    /// A "nice" upper bound for a chart's y-axis: at least `floor`, otherwise
    /// 20% above the largest value, rounded up to something readable.
    static func niceMax(_ values: [Double], floor: Double) -> Double {
        let peak = values.max() ?? 0
        let target = max(peak * 1.2, floor)
        let mag = pow(10, (log10(target)).rounded(.down))
        let step = mag <= 0 ? 1 : mag
        return (target / step).rounded(.up) * step
    }
}

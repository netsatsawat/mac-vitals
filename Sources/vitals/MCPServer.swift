import Foundation
import VitalsCore

/// A minimal Model Context Protocol server over stdio, with no third-party
/// dependencies. It speaks newline-delimited JSON-RPC 2.0: one request object per
/// line on stdin, one response object per line on stdout. Anything the server
/// wants to log goes to stderr, so it never corrupts the protocol stream.
///
/// It exposes two read-only tools, `get_vitals` and `get_vitals_history`, so an
/// AI agent can read this Mac's live state and never change it. A single
/// background thread owns the `Monitor` and refreshes shared state once a second,
/// which keeps all sampling on one thread and the request handlers lock-and-read.
final class MCPServer {
    private let protocolVersion = "2024-11-05"
    private let serverName = "mac-vitals"
    private let serverVersion = "0.2.1"

    private let lock = NSLock()
    private var latest: Snapshot = .placeholder
    private var history: [Snapshot] = []
    private let historyCapacity = 60
    private var trace: Trace?

    func run() -> Never {
        startSampler()
        let out = FileHandle.standardOutput
        while let line = readLine(strippingNewline: true) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
                  let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let response = handle(msg) {
                if let respData = try? JSONSerialization.data(withJSONObject: response) {
                    out.write(respData)
                    out.write(Data([0x0a])) // newline delimiter
                }
            }
        }
        exit(0)
    }

    // MARK: - Sampling

    private func startSampler() {
        Thread.detachNewThread { [self] in
            let monitor = Monitor()
            _ = monitor.sample()          // prime the delta baseline
            Thread.sleep(forTimeInterval: 0.4)
            store(monitor.sample())       // one real reading before serving
            while true {
                Thread.sleep(forTimeInterval: 1.0)
                store(monitor.sample())
            }
        }
    }

    private func store(_ s: Snapshot) {
        lock.lock(); defer { lock.unlock() }
        latest = s
        history.append(s)
        if history.count > historyCapacity { history.removeFirst(history.count - historyCapacity) }
        if trace != nil { trace!.add(s) }
    }

    private func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return latest }
    private func recent(_ n: Int) -> [Snapshot] {
        lock.lock(); defer { lock.unlock() }
        return Array(history.suffix(n))
    }

    // MARK: - JSON-RPC

    private func handle(_ msg: [String: Any]) -> [String: Any]? {
        let method = msg["method"] as? String ?? ""
        let id = msg["id"]                       // absent on notifications

        switch method {
        case "initialize":
            return reply(id, [
                "protocolVersion": protocolVersion,
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": serverName, "version": serverVersion],
            ])
        case "tools/list":
            return reply(id, ["tools": toolList])
        case "tools/call":
            return handleToolCall(msg, id: id)
        case "ping":
            return reply(id, [String: Any]())
        case "notifications/initialized", "notifications/cancelled":
            return nil                            // notifications get no response
        default:
            guard id != nil else { return nil }
            return errorReply(id, code: -32601, message: "method not found: \(method)")
        }
    }

    private var toolList: [[String: Any]] {
        [
            [
                "name": "get_vitals",
                "description": "One live reading of this Mac: CPU (overall, the efficiency and performance clusters, and per-core), GPU, memory (used/total, memory-pressure level, swap in use, and how much memory the GPU may use, which is the practical limit for fitting a local model), per-rail power in watts including the Neural Engine (ANE), network up/down bytes per second, disk read/write and free space, battery, and SoC temperature, fan RPM, and thermal-pressure state (serious or critical means the machine is throttling). Read-only.",
                "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            ],
            [
                "name": "get_vitals_history",
                "description": "Per-second history (up to the last 60 seconds) of CPU%, GPU%, memory%, and total power in watts. Useful for asking what a build or a run cost the machine.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "seconds": [
                            "type": "integer", "minimum": 1, "maximum": 60,
                            "description": "How many seconds of history to return (default 30).",
                        ],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "get_top_processes",
                "description": "The processes using this Mac the most right now, with CPU percent (of one core, so it can exceed 100) and memory in bytes. Answers 'what is using my machine' and, for local models, whether the model server (Ollama, LM Studio, and so on) is the one eating CPU or memory. Per-process GPU is not available to a normal user, so it is not reported. Read-only.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "limit": ["type": "integer", "minimum": 1, "maximum": 30, "description": "How many processes to return (default 8)."],
                        "sortBy": ["type": "string", "enum": ["cpu", "memory"], "description": "Sort by 'cpu' (default) or 'memory'."],
                    ],
                    "additionalProperties": false,
                ],
            ],
            [
                "name": "start_trace",
                "description": "Begin measuring what a task costs this Mac. Call this, run the work, then call stop_trace. Only one trace runs at a time; calling start again restarts it.",
                "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            ],
            [
                "name": "stop_trace",
                "description": "End the current trace and return what the work cost: duration, CPU and GPU average and peak, average watts and energy in watt-hours, network and disk totals, peak temperature, whether the machine thermally throttled during the run, and peak swap in use. Throttling or rising swap explains a run that slowed down.",
                "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            ],
        ]
    }

    private func handleToolCall(_ msg: [String: Any], id: Any?) -> [String: Any]? {
        let params = msg["params"] as? [String: Any] ?? [:]
        let name = params["name"] as? String ?? ""
        let args = params["arguments"] as? [String: Any] ?? [:]

        switch name {
        case "get_vitals":
            return toolText(id, jsonText(from: snapshot()))
        case "get_vitals_history":
            let seconds = (args["seconds"] as? Int) ?? 30
            return toolText(id, historyText(seconds: max(1, min(60, seconds))))
        case "get_top_processes":
            let limit = max(1, min(30, (args["limit"] as? Int) ?? 8))
            let byMemory = (args["sortBy"] as? String) == "memory"
            let procs = ProcessReader().topOnce(limit: limit, byMemory: byMemory)
            let text = (try? encoder().encode(procs)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            return toolText(id, text)
        case "start_trace":
            lock.lock(); trace = Trace(); lock.unlock()
            return toolText(id, "Trace started. Run the work, then call stop_trace.")
        case "stop_trace":
            lock.lock(); let finished = trace; trace = nil; lock.unlock()
            guard let finished else {
                return errorReply(id, code: -32602, message: "no active trace; call start_trace first")
            }
            return toolText(id, traceText(finished.result()))
        default:
            return errorReply(id, code: -32602, message: "unknown tool: \(name)")
        }
    }

    // MARK: - Encoding

    private func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private func jsonText(from snapshot: Snapshot) -> String {
        guard let data = try? encoder().encode(snapshot), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private func traceText(_ result: TraceResult) -> String {
        guard let data = try? encoder().encode(result), let s = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return s
    }

    private func historyText(seconds: Int) -> String {
        let samples = recent(seconds)
        let series: [[String: Any]] = samples.map { s in
            [
                "t": ISO8601DateFormatter().string(from: s.timestamp),
                "cpu": round1(s.cpu.usage),
                "gpu": round1(s.gpu.usage),
                "memory": round1(s.memory.usedPercent),
                "watts": round1(s.power.totalWatts),
            ]
        }
        let payload: [String: Any] = [
            "seconds": samples.count,
            "gpuProvisional": snapshot().gpu.provisional,
            "samples": series,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    private func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }

    // MARK: - Envelope helpers

    private func reply(_ id: Any?, _ result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result]
    }
    private func toolText(_ id: Any?, _ text: String) -> [String: Any] {
        reply(id, ["content": [["type": "text", "text": text]], "isError": false])
    }
    private func errorReply(_ id: Any?, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }
}

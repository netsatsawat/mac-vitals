#!/usr/bin/env python3
"""Integration test for the MCP server. Spawns `vitals --mcp`, runs a full
JSON-RPC session, and asserts each tool responds with the expected shape.
Exit 0 on pass, 1 on failure. Used locally and in CI.

    python3 scripts/test-mcp.py [path-to-vitals]
"""
import json
import subprocess
import sys
import threading
import time

BIN = sys.argv[1] if len(sys.argv) > 1 else ".build/release/vitals"
failures = []


def check(ok, msg):
    if not ok:
        failures.append(msg)


def main():
    proc = subprocess.Popen([BIN, "--mcp"], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True, bufsize=1)

    def feed():
        w = proc.stdin
        def send(obj):
            w.write(json.dumps(obj) + "\n"); w.flush()
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}})
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        time.sleep(1.6)  # let the sampler take a real reading
        send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
              "params": {"name": "get_vitals", "arguments": {}}})
        send({"jsonrpc": "2.0", "id": 6, "method": "tools/call",
              "params": {"name": "get_top_processes", "arguments": {"limit": 5}}})
        send({"jsonrpc": "2.0", "id": 4, "method": "tools/call",
              "params": {"name": "start_trace", "arguments": {}}})
        time.sleep(3)
        send({"jsonrpc": "2.0", "id": 5, "method": "tools/call",
              "params": {"name": "stop_trace", "arguments": {}}})
        time.sleep(0.3)
        w.close()  # EOF ends the server

    threading.Thread(target=feed, daemon=True).start()

    responses = {}
    for line in proc.stdout:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            failures.append("non-JSON line: " + line[:80]); continue
        if obj.get("id") is not None:
            responses[obj["id"]] = obj

    # initialize
    init = responses.get(1, {}).get("result", {})
    check(init.get("serverInfo", {}).get("name") == "mac-vitals", "initialize serverInfo wrong")
    check(init.get("protocolVersion"), "initialize missing protocolVersion")

    # tools/list
    tools = {t["name"] for t in responses.get(2, {}).get("result", {}).get("tools", [])}
    for name in ("get_vitals", "get_vitals_history", "get_top_processes", "start_trace", "stop_trace"):
        check(name in tools, "missing tool: " + name)

    # get_vitals content
    gv = responses.get(3, {}).get("result", {}).get("content", [{}])[0].get("text", "{}")
    vitals = json.loads(gv)
    for key in ("cpu", "gpu", "memory", "power", "network", "disk", "battery", "thermal", "timestamp"):
        check(key in vitals, "get_vitals missing key: " + key)
    check(0 <= vitals["cpu"]["usage"] <= 100, "cpu.usage out of range")
    check(vitals["memory"]["totalBytes"] > 0, "memory.totalBytes zero")

    # start_trace / stop_trace
    started = responses.get(4, {}).get("result", {}).get("content", [{}])[0].get("text", "")
    check("started" in started.lower(), "start_trace did not confirm")
    st = responses.get(5, {}).get("result", {}).get("content", [{}])[0].get("text", "{}")
    trace = json.loads(st)
    for key in ("durationSeconds", "cpuAvgPercent", "gpuAvgPercent", "energyWattHours",
                "networkDownBytes", "diskWriteBytes"):
        check(key in trace, "stop_trace missing key: " + key)
    check(trace["durationSeconds"] > 0, "trace duration not positive")
    for key in ("throttled", "peakSwapBytes"):
        check(key in trace, "stop_trace missing key: " + key)

    # get_top_processes content
    tp = responses.get(6, {}).get("result", {}).get("content", [{}])[0].get("text", "[]")
    procs = json.loads(tp)
    check(isinstance(procs, list) and len(procs) > 0, "get_top_processes returned no processes")
    if procs:
        for key in ("pid", "name", "cpuPercent", "memoryBytes"):
            check(key in procs[0], "process missing key: " + key)

    proc.wait(timeout=5)

    if failures:
        print("MCP test FAIL:")
        for f in failures:
            print("  - " + f)
        sys.exit(1)
    print("MCP test PASS: initialize, tools/list, get_vitals, start_trace/stop_trace all OK")


if __name__ == "__main__":
    main()

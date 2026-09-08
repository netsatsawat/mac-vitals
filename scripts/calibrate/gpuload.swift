// gpuload — saturate the GPU with a Metal compute loop for N seconds, so
// calibration has a clear high-load phase. Build: swiftc -O gpuload.swift -o gpuload
import Metal
import Foundation

let secs = CommandLine.arguments.count > 1 ? Double(CommandLine.arguments[1]) ?? 6 : 6
guard let dev = MTLCreateSystemDefaultDevice(), let q = dev.makeCommandQueue() else { exit(1) }
let src = """
#include <metal_stdlib>
using namespace metal;
kernel void spin(device float* buf [[buffer(0)]], uint id [[thread_position_in_grid]]) {
  float x = buf[id] + float(id) * 1e-6;
  for (int i=0;i<4000000;i++){ x = fma(x, 1.0000001f, 0.0000001f); x = sqrt(x*x+1.0f); }
  buf[id] = x;
}
"""
let pso = try dev.makeComputePipelineState(function: try dev.makeLibrary(source: src, options: nil).makeFunction(name: "spin")!)
let n = 1 << 18
let buf = dev.makeBuffer(length: n * 4, options: .storageModeShared)!
let deadline = Date().addingTimeInterval(secs)
let sem = DispatchSemaphore(value: 3)
while Date() < deadline {
    sem.wait()
    let cb = q.makeCommandBuffer()!
    cb.addCompletedHandler { _ in sem.signal() }
    let enc = cb.makeComputeCommandEncoder()!
    enc.setComputePipelineState(pso); enc.setBuffer(buf, offset: 0, index: 0)
    enc.dispatchThreads(MTLSize(width: n, height: 1, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: pso.maxTotalThreadsPerThreadgroup, height: 1, depth: 1))
    enc.endEncoding(); cb.commit()
}

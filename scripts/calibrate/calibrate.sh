#!/usr/bin/env bash
# GPU calibration: capture powermetrics' ground-truth GPU active residency and
# our IOReport GPUPH residency together, under load and at idle, so the GPUPH
# formula can be matched to powermetrics.
#
#   sudo bash scripts/calibrate/calibrate.sh
#
# powermetrics needs root; the rest does not. Paste the whole output back.
set -uo pipefail
cd "$(dirname "$0")"

[ -x ./gpucal ] || clang -fblocks gpucal.c -o gpucal -framework CoreFoundation
[ -x ./gpuload ] || swiftc -O gpuload.swift -o gpuload

pm() {
    powermetrics --samplers gpu_power -i 1000 -n 2 2>/dev/null \
        | grep -iE 'GPU HW active residency|GPU idle residency|GPU HW active frequency|GPU Power' | head -8
}

echo "############ PHASE 1: GPU UNDER LOAD ############"
./gpuload 12 >/dev/null 2>&1 &
LOAD=$!
sleep 2
echo "----- powermetrics (under load) -----"; pm
echo "----- IOReport GPUPH (under load) -----"; ./gpucal 1.0
kill "$LOAD" 2>/dev/null; wait "$LOAD" 2>/dev/null

echo ""
echo "############ PHASE 2: GPU IDLE — please don't touch the Mac ############"
sleep 4
echo "----- powermetrics (idle) -----"; pm
echo "----- IOReport GPUPH (idle) -----"; ./gpucal 1.0

echo ""
echo "############ DONE — paste everything above ############"

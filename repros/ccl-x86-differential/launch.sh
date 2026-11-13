#!/bin/sh
# launch.sh TOTAL NCHUNKS  -- fuzz [0,TOTAL) split into NCHUNKS, CCL+SBCL per chunk.
TOTAL=${1:-2000000}; NCHUNKS=${2:-10}
BASE=/home/hbox/ca-x86-ccl
RUNS=$BASE/runs; mkdir -p "$RUNS"
CRASH=$RUNS/crashes.log; : > "$CRASH"
CHUNK=$(( (TOTAL + NCHUNKS - 1) / NCHUNKS ))
pids=""
i=0
while [ "$i" -lt "$NCHUNKS" ]; do
  s=$(( i * CHUNK )); e=$(( s + CHUNK )); [ "$e" -gt "$TOTAL" ] && e=$TOTAL
  nohup setsid sh "$BASE/drive.sh" ccl  "$s" "$e" "$RUNS/ccl.$i.txt"  "$CRASH" >/dev/null 2>&1 &
  echo $! > "$RUNS/ccl.$i.pid"
  nohup setsid sh "$BASE/drive.sh" sbcl "$s" "$e" "$RUNS/sbcl.$i.txt" "$CRASH" >/dev/null 2>&1 &
  echo $! > "$RUNS/sbcl.$i.pid"
  i=$(( i + 1 ))
done
echo "launched $NCHUNKS chunks x 2 impls; chunk=$CHUNK; total=$TOTAL"
echo "pids in $RUNS/*.pid ; crash log $CRASH"

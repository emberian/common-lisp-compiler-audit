#!/bin/sh
# run-stage2.sh sbcl|ccl [PER_ATTEMPT_TIMEOUT_SECONDS] [MAX_ATTEMPTS]
# Runs stage2.lisp to completion.  stage2 appends one summary row per finished operator and
# names the operator in progress in results/HOST-current.txt.  If the Lisp process dies
# (host crash, heap exhaustion, timeout) the operator in progress is appended to
# results/HOST-crashed.txt and the run is resumed: an operator that crashed once is re-run
# with the reduced universe, one that crashed twice gets a HOST-CRASH row.
# Rows in HOST-signatures.tsv / HOST-violations.tsv of an operator with no summary row of
# its own (a crashed attempt) are removed at the end.
cd "$(dirname "$0")" || exit 2
echo $$ > results/$1-driver.pid
H=$1; T=${2:-3000}; N=${3:-40}
rm -f results/$H-summary.tsv results/$H-signatures.tsv results/$H-violations.tsv results/$H-crashed.txt results/$H-current.txt
i=0
while [ $i -lt $N ]; do
  i=$((i+1))
  PIDFILE=results/$H-stage2.pid ./run-$H.sh scratch/s2full.lisp "$T" > results/$H-stage2.log 2>&1
  if grep -q "STAGE2 DONE" results/$H-stage2.log; then echo "done after $i attempt(s)"; break; fi
  cat results/$H-current.txt >> results/$H-crashed.txt
  tail -3 results/$H-stage2.log | cut -c1-200 > results/$H-crash-$i.log
done

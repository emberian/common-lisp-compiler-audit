#!/bin/sh
# run.sh /path/to/sbcl [args-to-reach-sbcl...]
# Runs repro.lisp and prints the VERDICT line.  Examples:
#   run.sh /usr/bin/sbcl
#   run.sh /home/hbox/sbcl-2.6.8-x86-64-linux/run-sbcl.sh
HERE=$(cd "$(dirname "$0")" && pwd)
SBCL=${1:?path to sbcl}; shift 2>/dev/null
"$SBCL" "$@" --script "$HERE/repro.lisp"

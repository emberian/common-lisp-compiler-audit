from collections.abc import Mapping
from pathlib import Path
import os
import subprocess
import tempfile


COMMANDS = {
    "sbcl-head": [
        os.environ.get("SBCL_HEAD_RUNTIME", "/Users/ember/dev/sbcl/src/runtime/sbcl"),
        "--core",
        os.environ.get("SBCL_HEAD_CORE", "/Users/ember/dev/sbcl/output/sbcl.core"),
        "--noinform",
        "--disable-debugger",
        "--script",
    ],
    "sbcl-installed": [
        os.environ.get("SBCL_INSTALLED", "/opt/homebrew/bin/sbcl"),
        "--noinform",
        "--disable-debugger",
        "--script",
    ],
    "ccl": [
        os.environ.get("CCL", "/Users/ember/dev/ccl/darm64cl"),
        "-n",
        "--batch",
        "--load",
    ],
}
TIMEOUT_SECONDS = 60
HELPER = """(declaim (inline mask-signed))
(defun mask-signed (width value)
  (declare (type (unsigned-byte 16) width) (type integer value))
  (if (zerop width)
      0
      (if (logbitp (1- width) value)
          (dpb value (byte width 0) -1)
          (ldb (byte width 0) value))))

"""


def _lisp_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _arguments(args, test_id):
    items = args.items() if isinstance(args, Mapping) else args
    values = {}
    for name, value in items:
        if name in values:
            raise ValueError(f"test {test_id!r} has duplicate argument {name!r}")
        if type(value) is not int:
            raise TypeError(
                f"test {test_id!r} argument {name!r} must be an exact Python int"
            )
        values[name] = value
    if set(values) != {"x", "count"}:
        raise ValueError(f"test {test_id!r} must supply exactly the x and count arguments")
    return values["x"], values["count"]


def _test_source(test, interpreted):
    test_id = test["id"]
    printed_id = str(test_id)
    if "\t" in printed_id or "\n" in printed_id or "\r" in printed_id:
        raise ValueError(f"test id {test_id!r} cannot contain tabs or newlines")
    x, count = _arguments(test["args"], test_id)
    operator = "eval" if interpreted else "compile nil"
    id_literal = _lisp_string(printed_id)
    tab = "\t"
    expression = f"""'(lambda (x count)
             {test['declarations']}
             {test['form']})"""
    return f"""(handler-case
    (format t "~a{tab}~s~%" {id_literal}
            (multiple-value-list
             (funcall ({operator}
                       {expression})
                      {x} {count})))
  (error ()
    (format t "~a{tab}(:error)~%" {id_literal})))
"""


def write_script(tests, script_path, interpreted=False):
    tests = list(tests)
    printed_ids = [str(test["id"]) for test in tests]
    if len(set(printed_ids)) != len(printed_ids):
        raise ValueError("test ids must be unique when printed")
    source = HELPER + "\n".join(_test_source(test, interpreted) for test in tests)
    path = Path(script_path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(source, encoding="utf-8")
    return path


def _output_text(output):
    if output is None:
        return ""
    if isinstance(output, bytes):
        return output.decode("utf-8", errors="replace")
    return output


def _failure_message(implementation, script_path, returncode, stdout, stderr):
    return (
        f"{implementation} exited with status {returncode} while running {script_path}\n"
        f"stdout:\n{stdout}\nstderr:\n{stderr}"
    )


def run(tests, implementation, workdir, interpreted=False):
    if implementation not in COMMANDS:
        choices = ", ".join(sorted(COMMANDS))
        raise ValueError(f"unknown implementation {implementation!r}; choose from {choices}")
    tests = list(tests)
    workdir = Path(workdir)
    workdir.mkdir(parents=True, exist_ok=True)
    script_path = write_script(
        tests, workdir / f"lisprun-{implementation}.lisp", interpreted=interpreted
    )
    command = COMMANDS[implementation] + [str(script_path)]
    try:
        completed = subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        stdout = _output_text(exc.stdout)
        stderr = _output_text(exc.stderr)
        raise RuntimeError(
            f"{implementation} timed out after {TIMEOUT_SECONDS} seconds while running "
            f"{script_path}\nstdout:\n{stdout}\nstderr:\n{stderr}"
        ) from exc
    except OSError as exc:
        raise RuntimeError(
            f"could not run {implementation} command {command[0]!r}: {exc}"
        ) from exc

    stdout = completed.stdout
    stderr = completed.stderr
    if completed.returncode != 0:
        raise RuntimeError(
            _failure_message(
                implementation, script_path, completed.returncode, stdout, stderr
            )
        )

    tests_by_printed_id = {str(test["id"]): test for test in tests}
    results = {}
    for line in stdout.splitlines():
        printed_id, separator, result = line.partition("\t")
        if not separator or printed_id not in tests_by_printed_id:
            continue
        if printed_id in results:
            raise RuntimeError(
                f"{implementation} printed duplicate results for test id {printed_id!r}"
            )
        results[printed_id] = result

    missing = [
        printed_id for printed_id in tests_by_printed_id if printed_id not in results
    ]
    if missing:
        raise RuntimeError(
            f"{implementation} output is missing test ids: {', '.join(repr(x) for x in missing)}\n"
            f"stdout:\n{stdout}\nstderr:\n{stderr}"
        )
    return {test["id"]: results[str(test["id"])] for test in tests}


if __name__ == "__main__":
    check = {
        "id": "unary-truncate",
        "form": "(truncate x)",
        "args": {"x": 17, "count": 0},
        "declarations": "(declare (ignore count))",
        "expected": "(17 0)",
    }
    with tempfile.TemporaryDirectory() as directory:
        actual = run([check], "sbcl-installed", directory)[check["id"]]
    if actual != check["expected"]:
        raise SystemExit(f"self-check failed: expected {check['expected']}, got {actual}")
    print(f"self-check passed: {actual}")

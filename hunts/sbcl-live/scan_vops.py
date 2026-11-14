#!/usr/bin/env python3
"""
Static analyzer for SBCL 2.6.10 VOP register-lifetime hazards (x86-64 & arm64).
Targets siblings of 0fd47cc68, 5093bbe40, 7b1c0e063, 480d58309, d4f4b504c, ae3dc4896.
"""
import os
import re
import sys
import subprocess
from dataclasses import dataclass, field
from typing import List, Optional, Dict, Tuple, Any, Set

# --- S-expression tokenizer & parser ---

TOKEN_RE = re.compile(
    r"""(?mx)
    \s+ |
    ;[^\n]* |
    \#\|[\s\S]*?\|\# |
    "(?:\\.|[^"\\])*" |
    \#\\. |
    \#[+-] |
    ,@ |
    ['`,()] |
    [^\s()'`,;"]+
    """
)

def parse_sexprs(text: str, filename: str = ""):
    tokens = []
    line_starts = [0]
    for idx, ch in enumerate(text):
        if ch == "\n":
            line_starts.append(idx + 1)

    def offset_to_line(off: int) -> int:
        lo, hi = 0, len(line_starts) - 1
        while lo <= hi:
            mid = (lo + hi) // 2
            if line_starts[mid] <= off:
                lo = mid + 1
            else:
                hi = mid - 1
        return hi + 1

    pos = 0
    n = len(text)
    while pos < n:
        # Handle nested #| ... |# comments properly
        if text.startswith("#|", pos):
            depth = 1
            pos += 2
            while pos < n and depth > 0:
                if text.startswith("#|", pos):
                    depth += 1
                    pos += 2
                elif text.startswith("|#", pos):
                    depth -= 1
                    pos += 2
                else:
                    pos += 1
            continue
        m = TOKEN_RE.match(text, pos)
        if not m:
            pos += 1
            continue
        tok = m.group(0)
        start = pos
        pos = m.end()
        if not tok or tok[0].isspace() or tok.startswith(";"):
            continue
        tokens.append((tok, offset_to_line(start)))

    idx = 0
    tlen = len(tokens)

    def read_one():
        nonlocal idx
        while idx < tlen:
            tok, line = tokens[idx]
            idx += 1
            if tok == "(":
                lst = []
                while idx < tlen and tokens[idx][0] != ")":
                    item = read_one()
                    if item is not None:
                        lst.append(item)
                if idx < tlen and tokens[idx][0] == ")":
                    idx += 1
                return SList(lst, line)
            elif tok == ")":
                return None
            elif tok in ("'", "`", ",", ",@"):
                sub = read_one()
                return SList([tok, sub], line)
            elif tok in ("#+", "#-"):
                _feat = read_one()
                body = read_one()
                # Keep body so conditional VOPs/operands are still analyzed
                return body
            elif tok == "#.":
                sub = read_one()
                return SList(["#.", sub], line)
            else:
                return SAtom(tok, line)
        return None

    forms = []
    while idx < tlen:
        f = read_one()
        if f is not None:
            forms.append(f)
    return forms

class SAtom(str):
    def __new__(cls, val, line=0):
        obj = super().__new__(cls, val)
        obj.line = line
        return obj

class SList(list):
    def __init__(self, items, line=0):
        super().__init__(items)
        self.line = line

def sym(x) -> str:
    if isinstance(x, SAtom):
        s = str(x).lower()
        if s.startswith(","):
            s = s.lstrip(",@")
        return s
    return ""

def is_kw(x, kw: str) -> bool:
    return isinstance(x, SAtom) and str(x).lower() == kw.lower()

def parse_time_spec(spec) -> int:
    phases = {":load": 0, ":argument": 1, ":eval": 2, ":result": 3, ":save": 4}
    if isinstance(spec, SAtom):
        ph = phases.get(sym(spec), 0)
        return ph << 16
    if isinstance(spec, SList) and len(spec) >= 2:
        ph = phases.get(sym(spec[0]), 0)
        try:
            sub = int(str(spec[1]))
        except ValueError:
            sub = 0
        return (ph << 16) + sub
    return 0

def fmt_time(t: int) -> str:
    ph = t >> 16
    sub = t & 0xFFFF
    names = {0: ":load", 1: ":argument", 2: ":eval", 3: ":result", 4: ":save"}
    nm = names.get(ph, f"phase{ph}")
    return f"({nm} {sub})" if ph in (1, 3) else nm

@dataclass
class Operand:
    name: str
    pair_of: Optional[str]
    pair_slot: Optional[int]  # 0=even(lo), 1=odd(hi) for register pairs
    kind: str  # 'arg', 'res', 'temp'
    index: int
    born: int
    dies: int
    has_explicit_from: bool = False
    has_explicit_to: bool = False
    scs: List[str] = field(default_factory=list)
    offset: Optional[str] = None
    target: Optional[str] = None
    unused_if: bool = False

@dataclass
class VopDef:
    name: str
    inherits: Optional[str]
    file: str
    line: int
    translate: List[str]
    args: List[Operand]
    results: List[Operand]
    temps: List[Operand]
    generator: Optional[SList]
    raw: SList

FP_SC_HINTS = ("float", "single", "double", "complex", "simd", "neon", "xmm", "ymm", "zmm")

def sc_family(scs: List[str]) -> str:
    if not scs:
        return "gpr"
    has_gpr = False
    has_fp = False
    for s in scs:
        sl = s.lower()
        if any(k in sl for k in ("stack", "constant", "immediate", "zero", "null")):
            continue
        if any(k in sl for k in FP_SC_HINTS):
            has_fp = True
        else:
            has_gpr = True
    if has_gpr and has_fp:
        return "both"
    if has_fp:
        return "fp"
    if has_gpr:
        return "gpr"
    return "nonreg"

def sc_compatible(op1: Operand, op2: Operand) -> bool:
    if op1.pair_slot is not None and op2.pair_slot is not None:
        if op1.pair_slot != op2.pair_slot:
            return False
    f1 = sc_family(op1.scs)
    f2 = sc_family(op2.scs)
    if "nonreg" in (f1, f2):
        return False
    if "both" in (f1, f2):
        return True
    return f1 == f2

def extract_vops_from_form(form, filename: str, out: List[VopDef]):
    if not isinstance(form, SList) or len(form) == 0:
        return
    head = sym(form[0])
    if head == "define-vop" and len(form) >= 2:
        vop = parse_define_vop(form, filename)
        if vop:
            out.append(vop)
        return
    for sub in form:
        extract_vops_from_form(sub, filename, out)

def parse_operand_list(clauses: List[Any], kind: str) -> List[Operand]:
    ops = []
    for idx, spec in enumerate(clauses):
        if not isinstance(spec, SList) or len(spec) == 0:
            continue
        first = spec[0]
        names = []
        pair_name = None
        is_pair = False
        if isinstance(first, SList):
            is_pair = True
            pair_name = "(" + " ".join(sym(x) for x in first) + ")"
            names = [sym(x) for x in first if sym(x)]
        else:
            nm = sym(first)
            if nm:
                names = [nm]
        born = 0 if kind == "arg" else ((3 << 16) + idx)
        dies = ((1 << 16) + idx) if kind == "arg" else (4 << 16)
        has_from = False
        has_to = False
        scs = []
        target = None
        is_more = False
        j = 1
        while j + 1 < len(spec):
            k = sym(spec[j])
            v = spec[j + 1]
            if k == ":scs" and isinstance(v, SList):
                scs = [sym(x) for x in v if sym(x)]
            elif k == ":to":
                dies = parse_time_spec(v)
                has_to = True
            elif k == ":from":
                born = parse_time_spec(v)
                has_from = True
            elif k == ":target":
                target = sym(v)
            elif k == ":more" and sym(v) != "nil":
                is_more = True
            j += 2
        if is_more:
            continue
        for s_idx, nm in enumerate(names):
            ops.append(Operand(
                name=nm, pair_of=pair_name, pair_slot=(s_idx if is_pair else None),
                kind=kind, index=idx,
                born=born, dies=dies, has_explicit_from=has_from, has_explicit_to=has_to,
                scs=scs, target=target
            ))
    return ops

def parse_temp_clause(spec: SList) -> List[Operand]:
    if len(spec) < 2 or not isinstance(spec[1], SList):
        return []
    opts = spec[1]
    names = [sym(x) for x in spec[2:] if sym(x)]
    born = 0
    dies = 4 << 16
    has_from = False
    has_to = False
    scs = []
    offset = None
    target = None
    unused_if = False
    j = 0
    while j + 1 < len(opts):
        k = sym(opts[j])
        v = opts[j + 1]
        if k == ":sc":
            scs = [sym(v)]
        elif k == ":scs" and isinstance(v, SList):
            scs = [sym(x) for x in v if sym(x)]
        elif k == ":offset":
            offset = sym(v) or str(v)
        elif k == ":from":
            born = parse_time_spec(v)
            has_from = True
        elif k == ":to":
            dies = parse_time_spec(v)
            has_to = True
        elif k == ":target":
            target = sym(v)
        elif k == ":unused-if":
            unused_if = True
        j += 2
    if not names and offset:
        names = [f"<wired:{offset}>"]
    return [
        Operand(name=nm, pair_of=None, pair_slot=None, kind="temp", index=0,
                born=born, dies=dies, has_explicit_from=has_from, has_explicit_to=has_to,
                scs=scs, offset=offset, target=target, unused_if=unused_if)
        for nm in names
    ]

def parse_define_vop(form: SList, filename: str) -> Optional[VopDef]:
    hdr = form[1]
    name = "<anon>"
    inherits = None
    if isinstance(hdr, SList):
        if len(hdr) >= 1 and sym(hdr[0]):
            name = sym(hdr[0])
        if len(hdr) >= 2 and sym(hdr[1]):
            inherits = sym(hdr[1])
    elif isinstance(hdr, SAtom):
        name = sym(hdr)

    translate = []
    args = []
    results = []
    temps = []
    gen = None
    for clause in form[2:]:
        if not isinstance(clause, SList) or len(clause) == 0:
            continue
        ck = sym(clause[0])
        if ck == ":translate":
            translate = [sym(x) for x in clause[1:] if sym(x)]
        elif ck == ":args":
            args = parse_operand_list(clause[1:], "arg")
        elif ck == ":results":
            results = parse_operand_list(clause[1:], "res")
        elif ck == ":temporary":
            temps.extend(parse_temp_clause(clause))
        elif ck == ":generator" and len(clause) >= 3:
            gen = SList(clause[2:], clause.line)

    return VopDef(
        name=name, inherits=inherits, file=filename, line=form.line,
        translate=translate, args=args, results=results, temps=temps,
        generator=gen, raw=form
    )

# --- Instruction read/write extraction ---

# Instructions on x86-64/arm64 that ONLY read their operands (do not write 1st operand)
READ_ONLY_INSTS = {
    "cmp", "cmn", "test", "tst", "bt", "ucomisd", "ucomiss", "comisd", "comiss",
    "fcmp", "fcmpe", "ccmp", "ccmn",
    "jmp", "je", "jne", "jz", "jnz", "jg", "jge", "jl", "jle", "ja", "jae", "jb", "jbe",
    "jo", "jno", "js", "jns", "jp", "jnp", "JCXZ", "jecxz", "jrcxz",
    "b", "bl", "br", "blr", "ret", "cbz", "cbnz", "tbz", "tbnz", "tbz*", "tbnz*",
    "str", "strb", "strh", "stur", "sturb", "sturh", "stp", "stlr", "stlxr",
    "push", "call", "nop", "brk", "ud2", "hlt", "dmb", "dsb", "isb",
}

# x86-64 2-operand read-modify-write instructions (1st operand is BOTH read and written)
X86_RMW_INSTS = {
    "add", "adc", "sub", "sbb", "and", "or", "xor", "imul",
    "shl", "shr", "sal", "sar", "rol", "ror", "shld", "shrd",
    "bts", "btr", "btc", "neg", "not", "inc", "dec", "bswap",
    "cmov", "cmove", "cmovne", "cmovz", "cmovnz", "cmovg", "cmovge", "cmovl", "cmovle",
    "cmova", "cmovae", "cmovb", "cmovbe", "cmovs", "cmovns", "cmovo", "cmovno",
    "xadd",
}

def collect_atoms(expr, known: Set[str]) -> Set[str]:
    out = set()
    if isinstance(expr, SAtom):
        s = sym(expr)
        if s in known:
            out.add(s)
    elif isinstance(expr, SList):
        # Don't treat (@ base ...) in store target as register write, handled by caller
        for sub in expr:
            out |= collect_atoms(sub, known)
    return out

def is_mem_ea(expr) -> bool:
    if isinstance(expr, SList) and len(expr) > 0:
        return sym(expr[0]) in ("@", "ea", "make-ea", "dword-ea", "byte-ea", "word-ea", "qword-ea")
    return False

def unwrap_reg(expr, known: Set[str]) -> Optional[str]:
    """If expr refers directly to a register TN (e.g. x, (32-bit-reg x), (reg-in-size x :dword)), return its name."""
    if isinstance(expr, SAtom):
        s = sym(expr)
        return s if s in known else None
    if isinstance(expr, SList) and len(expr) >= 2:
        h = sym(expr[0])
        if h in ("32-bit-reg", "reg-in-size", "dword-reg", "word-reg", "byte-reg", "single-reg", "double-reg"):
            return unwrap_reg(expr[1], known)
    return None

def analyze_stmt_events(expr, arch: str, known: Set[str], guarded: Set[str], events: List[Tuple[str, str, int, Set[str], str]]):
    """
    Walk generator body in order, recording ('read'|'write', op_name, line, guarded_vars, context_str).
    Inside (cond ...) / (if ...) / (case ...), analyzes each branch independently so false cross-branch
    write->read pairs are NOT mixed!
    """
    if not isinstance(expr, SList) or len(expr) == 0:
        r = collect_atoms(expr, known)
        for v in r:
            events.append(("read", v, getattr(expr, "line", 0), set(guarded), str(expr)))
        return

    h = sym(expr[0])
    line = expr.line

    # Branching constructs: fork event stream per branch?
    # Wait: code AFTER (cond ...) executes AFTER whichever branch ran!
    # So we handle sequential lists specially in walk_seq!
    if h == "move" and len(expr) >= 3:
        dst = unwrap_reg(expr[1], known)
        srcs = collect_atoms(expr[2], known)
        for s in srcs:
            events.append(("read", s, line, set(guarded), f"(move {expr[1]} {expr[2]})"))
        if dst:
            # Self-move (move x x) is a no-op if dst == src
            events.append(("write", dst, line, set(guarded), f"(move {expr[1]} {expr[2]})"))
        return

    if h in ("zeroize", "load-immediate", "loadw", "load-symbol-value", "load-stack-tn") and len(expr) >= 2:
        # First arg is destination (except load-immediate vop x y)
        if h == "load-immediate" and len(expr) >= 4:
            dst = unwrap_reg(expr[3], known)
            srcs = collect_atoms(expr[2], known)
        else:
            dst = unwrap_reg(expr[1], known)
            srcs = set()
            for sub in expr[2:]:
                srcs |= collect_atoms(sub, known)
        for s in srcs:
            events.append(("read", s, line, set(guarded), f"({h} ...)"))
        if dst:
            events.append(("write", dst, line, set(guarded), f"({h} ...)"))
        return

    if h == "inst" and len(expr) >= 2:
        inst_idx = 1
        op = sym(expr[1])
        # On x86-64, (inst mov :dword dst src) has size keyword first or second
        operands = expr[2:]
        if operands and sym(operands[0]).startswith(":"):
            operands = operands[1:]
        if op.startswith(":") and operands:
            op = sym(operands[0])
            operands = operands[1:]

        # Filter size keywords at end like :dword :qword
        clean_ops = [o for o in operands if not (isinstance(o, SAtom) and sym(o).startswith(":"))]
        ctx = f"(inst {op} " + " ".join(str(o) for o in operands[:3]) + ")"

        if op in READ_ONLY_INSTS:
            for o in operands:
                for s in collect_atoms(o, known):
                    events.append(("read", s, line, set(guarded), ctx))
            return

        if arch == "arm64" and op in ("ldp",):
            # (inst ldp r1 r2 (@ base ...))
            if len(clean_ops) >= 3:
                for o in clean_ops[2:]:
                    for s in collect_atoms(o, known):
                        events.append(("read", s, line, set(guarded), ctx))
                for d_expr in clean_ops[:2]:
                    d = unwrap_reg(d_expr, known)
                    if d:
                        events.append(("write", d, line, set(guarded), ctx))
                return

        if arch == "x86-64" and op == "xchg" and len(clean_ops) >= 2:
            d1 = unwrap_reg(clean_ops[0], known)
            d2 = unwrap_reg(clean_ops[1], known)
            for o in clean_ops:
                for s in collect_atoms(o, known):
                    events.append(("read", s, line, set(guarded), ctx))
            if d1:
                events.append(("write", d1, line, set(guarded), ctx))
            if d2:
                events.append(("write", d2, line, set(guarded), ctx))
            return

        if arch == "x86-64" and op in ("mul", "imul") and len(clean_ops) == 1:
            # 1-operand mul/imul reads rax and operand, writes rax and rdx!
            for s in collect_atoms(clean_ops[0], known):
                events.append(("read", s, line, set(guarded), ctx))
            for rname in ("rax", "eax", "rax-tn"):
                if rname in known:
                    events.append(("read", rname, line, set(guarded), ctx))
                    events.append(("write", rname, line, set(guarded), ctx))
            for dname in ("rdx", "edx", "rdx-tn"):
                if dname in known:
                    events.append(("write", dname, line, set(guarded), ctx))
            return

        if arch == "x86-64" and op in ("div", "idiv") and len(clean_ops) >= 1:
            for s in collect_atoms(clean_ops[-1], known):
                events.append(("read", s, line, set(guarded), ctx))
            for rname in ("rax", "rdx"):
                if rname in known:
                    events.append(("read", rname, line, set(guarded), ctx))
                    events.append(("write", rname, line, set(guarded), ctx))
            return

        if arch == "x86-64" and op in ("cqo", "cdq"):
            if "rax" in known:
                events.append(("read", "rax", line, set(guarded), ctx))
            if "rdx" in known:
                events.append(("write", "rdx", line, set(guarded), ctx))
            return

        if len(clean_ops) >= 1:
            first_op = clean_ops[0]
            if is_mem_ea(first_op):
                # Memory destination: all registers inside EA and source operands are READ!
                for o in clean_ops:
                    for s in collect_atoms(o, known):
                        events.append(("read", s, line, set(guarded), ctx))
                return
            dst = unwrap_reg(first_op, known)
            # Check x86 xor r, r (zeroing idiom: does NOT depend on old r, ONLY writes r!)
            if arch == "x86-64" and op == "xor" and len(clean_ops) == 2:
                d2 = unwrap_reg(clean_ops[1], known)
                if dst and dst == d2:
                    events.append(("write", dst, line, set(guarded), ctx))
                    return
            # Reads from remaining operands:
            for o in clean_ops[1:]:
                for s in collect_atoms(o, known):
                    events.append(("read", s, line, set(guarded), ctx))
            # On x86-64 RMW instructions, dst is ALSO read!
            if arch == "x86-64" and dst and (op in X86_RMW_INSTS or op.startswith("cmov")):
                events.append(("read", dst, line, set(guarded), ctx))
            # Check implicit :cl read on x86-64 variable shifts
            if arch == "x86-64" and any(isinstance(o, SAtom) and sym(o) == ":cl" for o in operands):
                for cname in ("ecx", "rcx", "ecx-tn", "rcx-tn"):
                    if cname in known:
                        events.append(("read", cname, line, set(guarded), ctx))
            if dst:
                events.append(("write", dst, line, set(guarded), ctx))
            return

    # Control flow and binding forms
    for sub in expr[1:]:
        analyze_stmt_events(sub, arch, known, guarded, events)

def extract_location_eq_vars(test_expr, known: Set[str]) -> Set[Any]:
    out = set()
    if isinstance(test_expr, SList) and len(test_expr) > 0:
        h = sym(test_expr[0])
        if h == "location=":
            atoms = list(collect_atoms(test_expr, known))
            for i in range(len(atoms)):
                for j in range(i + 1, len(atoms)):
                    out.add(frozenset((atoms[i], atoms[j])))
        else:
            for sub in test_expr:
                out |= extract_location_eq_vars(sub, known)
    return out

def enumerate_paths(stmts: List[Any], arch: str, known: Set[str], guarded: Set[Any], max_paths: int = 32) -> List[List[Tuple[str, str, int, Set[Any], str]]]:
    """Expand top-level cond/if/when/unless/let into execution paths (bounded)."""
    paths = [[]]
    for st in stmts:
        if not isinstance(st, SList) or len(st) == 0:
            continue
        h = sym(st[0])
        if h in ("progn", "assemble"):
            body = st[2:] if h == "assemble" and len(st) >= 2 and isinstance(st[1], SList) else st[1:]
            sub_paths = enumerate_paths(body, arch, known, guarded, max_paths)
            paths = [p + sp for p in paths for sp in sub_paths][:max_paths]
        elif h in ("let", "let*") and len(st) >= 3 and isinstance(st[1], SList):
            bind_ev = []
            for b in st[1]:
                if isinstance(b, SList) and len(b) >= 2:
                    analyze_stmt_events(b[1], arch, known, guarded, bind_ev)
            sub_paths = enumerate_paths(st[2:], arch, known, guarded, max_paths)
            paths = [p + bind_ev + sp for p in paths for sp in sub_paths][:max_paths]
        elif h == "cond":
            branch_paths = []
            accum_guards = set(guarded)
            saw_t = False
            for clause in st[1:]:
                if not isinstance(clause, SList) or len(clause) == 0:
                    continue
                test = clause[0]
                if sym(test) == "t":
                    saw_t = True
                g = extract_location_eq_vars(test, known)
                accum_guards |= g
                bp = enumerate_paths(clause[1:], arch, known, accum_guards, max_paths)
                branch_paths.extend(bp)
            if not saw_t:
                branch_paths.append([])
            if branch_paths:
                paths = [p + bp for p in paths for bp in branch_paths][:max_paths]
        elif h == "if" and len(st) >= 3:
            g = guarded | extract_location_eq_vars(st[1], known)
            p_then = enumerate_paths([st[2]], arch, known, g, max_paths)
            p_else = enumerate_paths(st[3:4], arch, known, g, max_paths) if len(st) >= 4 else [[]]
            paths = [p + bp for p in paths for bp in (p_then + p_else)][:max_paths]
        elif h in ("when", "unless") and len(st) >= 3:
            g = guarded | extract_location_eq_vars(st[1], known)
            p_body = enumerate_paths(st[2:], arch, known, g, max_paths)
            paths = [p + bp for p in paths for bp in (p_body + [[]])][:max_paths]
        else:
            ev = []
            analyze_stmt_events(st, arch, known, guarded, ev)
            for p in paths:
                p.extend(ev)
    return paths

def merge_operand_from_parent(child_ops: List[Operand], parent_ops: List[Operand]) -> List[Operand]:
    if not child_ops:
        return [Operand(**vars(op)) for op in parent_ops]
    p_by_name = {op.name: op for op in parent_ops}
    merged = []
    for cop in child_ops:
        pop = p_by_name.get(cop.name)
        if pop is not None:
            born = cop.born if cop.has_explicit_from else pop.born
            dies = cop.dies if cop.has_explicit_to else pop.dies
            has_from = cop.has_explicit_from or pop.has_explicit_from
            has_to = cop.has_explicit_to or pop.has_explicit_to
            scs = cop.scs if cop.scs else pop.scs
            target = cop.target if cop.target else pop.target
            merged.append(Operand(
                name=cop.name, pair_of=cop.pair_of or pop.pair_of,
                pair_slot=cop.pair_slot if cop.pair_slot is not None else pop.pair_slot,
                kind=cop.kind, index=cop.index,
                born=born, dies=dies, has_explicit_from=has_from, has_explicit_to=has_to,
                scs=scs, offset=cop.offset or pop.offset, target=target, unused_if=cop.unused_if
            ))
        else:
            merged.append(cop)
    return merged

def resolve_inheritance(vops: List[VopDef]) -> List[VopDef]:
    by_name = {v.name: v for v in vops if v.name != "<anon>"}
    resolved = set()

    def resolve_one(v: VopDef, stack: Set[str]):
        if id(v) in resolved:
            return
        if v.inherits and v.inherits in by_name and v.inherits not in stack:
            p = by_name[v.inherits]
            resolve_one(p, stack | {v.inherits})
            v.args = merge_operand_from_parent(v.args, p.args)
            v.results = merge_operand_from_parent(v.results, p.results)
            c_tnames = {t.name for t in v.temps}
            v.temps = [Operand(**vars(t)) for t in p.temps if t.name not in c_tnames] + v.temps
            if v.generator is None:
                v.generator = p.generator
        resolved.add(id(v))

    for v in vops:
        resolve_one(v, {v.name} if v.name != "<anon>" else set())
    return vops

def audit_backend(git_dir: str, tag: str, arch: str):
    ls = subprocess.check_output(
        ["git", "ls-tree", "-r", "--name-only", tag, f"src/compiler/{arch}/"],
        cwd=git_dir, text=True
    ).splitlines()
    vops: List[VopDef] = []
    for rel in sorted(ls):
        if not rel.endswith(".lisp"):
            continue
        src = subprocess.check_output(["git", "show", f"{tag}:{rel}"], cwd=git_dir, text=True)
        forms = parse_sexprs(src, rel)
        for f in forms:
            extract_vops_from_form(f, rel, vops)

    resolve_inheritance(vops)
    findings = []

    for v in vops:
        if not v.generator:
            continue
        op_map: Dict[str, Operand] = {}
        for a in v.args:
            op_map[a.name] = a
        for r in v.results:
            op_map[r.name] = r
        for t in v.temps:
            op_map[t.name] = t
        known = set(op_map.keys())
        if not known:
            continue

        paths = enumerate_paths(list(v.generator), arch, known, set(), max_paths=48)
        seen_for_vop = set()

        for path in paths:
            written: Dict[str, Tuple[int, Set[Any], str]] = {}
            for kind, var, line, gvars, ctx in path:
                if kind == "read":
                    if var not in op_map or op_map[var].kind != "arg":
                        continue
                    arg_op = op_map[var]
                    # Check if ANY previously-written result or temp in this path could alias arg_op!
                    for wvar, (wline, wgvars, wctx) in written.items():
                        if wvar == var:
                            continue
                        wop = op_map.get(wvar)
                        if not wop or wop.kind not in ("res", "temp"):
                            continue
                        # Do wop and arg_op conflict in SBCL's lifetime model?
                        # Remember meta-vmdef.lisp:612: if wop.born >= arg_op.dies, they DO NOT CONFLICT!
                        if wop.born < arg_op.dies:
                            continue
                        if not sc_compatible(wop, arg_op):
                            continue
                        pair_key = frozenset((var, wvar))
                        is_guarded = (pair_key in gvars or pair_key in wgvars)
                        key = (wop.kind, wvar, var, is_guarded)
                        if key in seen_for_vop:
                            continue
                        seen_for_vop.add(key)
                        severity = "GUARDED-CHECK" if is_guarded else (
                            "HIGH-WIRED-TEMP" if (wop.kind == "temp" and wop.offset) else
                            "HIGH-EARLY-TEMP" if wop.kind == "temp" else
                            "HIGH-RESULT-CLOBBER"
                        )
                        findings.append({
                            "arch": arch,
                            "severity": severity,
                            "file": v.file,
                            "line": v.line,
                            "vop": v.name,
                            "translate": v.translate,
                            "writer_kind": wop.kind,
                            "writer": wvar,
                            "writer_born": fmt_time(wop.born),
                            "writer_offset": wop.offset,
                            "writer_scs": wop.scs,
                            "arg": var,
                            "arg_dies": fmt_time(arg_op.dies),
                            "arg_scs": arg_op.scs,
                            "wline": wline,
                            "wctx": wctx,
                            "rline": line,
                            "rctx": ctx,
                        })
                elif kind == "write":
                    if var not in written:
                        written[var] = (line, gvars, ctx)

    return vops, findings

if __name__ == "__main__":
    git_dir = sys.argv[1]
    tag = sys.argv[2] if len(sys.argv) > 2 else "sbcl-2.6.10"
    for arch in ("x86-64", "arm64"):
        vops, findings = audit_backend(git_dir, tag, arch)
        high = [f for f in findings if not f["severity"].startswith("GUARDED")]
        print(f"=== {arch}: parsed {len(vops)} VOPs, {len(high)} UNGUARDED lifetime candidates ({len(findings)} total incl guarded) ===")
        for f in high:
            print(
                f"[{f['severity']}] {f['file']}:{f['line']} vop={f['vop']} tr={f['translate']} | "
                f"writes {f['writer_kind']} `{f['writer']}` (born={f['writer_born']}, off={f['writer_offset']}, scs={f['writer_scs']}) "
                f"@L{f['wline']} `{f['wctx']}` BEFORE reading arg `{f['arg']}` (dies={f['arg_dies']}, scs={f['arg_scs']}) "
                f"@L{f['rline']} `{f['rctx']}`"
            )

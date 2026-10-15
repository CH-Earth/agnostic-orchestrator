# AGENTS.md — Orchestrator corrections: HPC validation and follow-up

## Context

This file replaces the previous correction brief, which is complete. All
correction work lives in the branch **`orchestrator-corrections`**;
`main` is intentionally untouched.

The reconciled and corrected orchestrator must now be validated on the
HPC (Linux, GNU userland, real SLURM) and, once validated, back-ported
into `kasra-keshavarz/model-agnostic-framework-publication` under
`4-orchestration/` (`orchestrator.sh` and `assets/json-funcs.jq`).

### Commits in this branch

| Commit | Purpose |
|---|---|
| `102ad7e` | Verbatim reconciliation with `model-agnostic-framework-publication/4-orchestration` |
| `745a550` | Colon-joined `afterok` dependencies, level-based parent tracking, configuration validation |
| `34e5960` | Independent (`order = -1`) processes submitted through the unified submission path |
| `752414d` | Robust component-key access, `.args` element validation, per-submission cache names, PID-stamped run artifacts |
| (this file) | HPC validation and follow-up guide |

### What was already validated on macOS

The logic below was verified on macOS with temporary compatibility shims
(macOS ships bash 3.2 without `mapfile`, and BSD sed):

- linear hierarchy, fan-out siblings, level gaps, multiple `args` objects
  per process, multiple parent IDs (`afterok:id1:id2`), independents kept
  out of the chain, bad configurations failing with clear errors, runtime
  artifacts — using mock `sbatch` / interface executables.

HPC validation must now confirm two things that macOS cannot:

1. the GNU/Linux toolchain behavior (real `mapfile`, GNU
   `sed -i "Ni\..."` insertion, GNU `realpath`), and
2. that real SLURM accepts the generated directives and enforces the
   dependencies.

## Files under validation

- `orchestrator.sh` — main script
- `assets/json-funcs.jq` — jq helpers
- `example/model-orchestration.json` — documentation only; paths are
  placeholders, **do not execute as-is**

## Acceptance reference (intended semantics)

- `order = -1`: independent; submitted through the same template or
  interface path as the first level but without any dependency; its job
  IDs are recorded in the log only and never used as parents.
- Positive `order` values: distinct execution levels, submitted in
  ascending order; every invocation of a level receives an `afterok`
  dependency on **all** submission IDs from the immediately preceding
  populated level only; siblings (same level, including multiple `args`
  objects of one process) never depend on each other.
- Template path: a cached copy of the template receives
  `#SBATCH --parsable` and — beyond the first level —
  `#SBATCH --dependency=afterok:id1:id2:...`; the invocation is appended
  as `srun <exec> <args> 2>> <log>` before `sbatch` is called.
- Interface path (empty `submission`): called as
  `<exec> --parsable <args> [--dependency=id1:id2:...]`; the component
  must submit the job itself and return the parsable job ID. Components
  such as datatool's `extract-dataset.sh` and gistool's
  `extract-gis.sh` prepend `afterok:` themselves, hence the bare
  colon-joined ID list.
- A failed parent permanently prevents its dependents from becoming
  eligible to run (SLURM `afterok` semantics); no orchestrator-side
  retry. `afterok` makes a job eligible, not guaranteed to run.
- Configuration checks: identical component keys across the four
  sections; value types; `order` value `-1` or positive integer (`0` is
  an error); submission templates and path-like executables present
  before any submission; failure aborts the run.
- Every submission is recorded in the log as
  `event=submit timestamp=... level=... process=... invocation=... dependency_ids=... job_id=...`.

## Phase 0 — environment checks (no submissions)

Run from the root of the `orchestrator-corrections` checkout:

```console
bash --version | head -1        # expect GNU bash >= 4.0 (DRA: 4.2 / 4.4 / 5.x)
sed --version | head -1         # expect GNU sed
jq --version                    # expect >= 1.5
realpath --version | head -1    # GNU coreutils
sbatch --version | head -1
bash -n orchestrator.sh && echo "syntax OK"
```

If the userland is not GNU (e.g. `sed` is not GNU sed), stop and report;
do not modify the script around environment problems.

## Phase A — mock end-to-end validation (no scheduler resources)

Everything below runs on a login node and submits nothing. The mock
`sbatch` shadows the real one through `PATH`; the mock component
interface mimics the datatool/gistool contract from
`2-model-agnostic/README.md` (it records the raw `--dependency` value
and renders `afterok:<value>` exactly like those scripts do). The
sandbox lives under `$HOME` so it is also visible from compute nodes
(used again in Phase C).

```bash
SANDBOX="$(mktemp -d "$HOME/orch-test.XXXXXX")"
mkdir -p "$SANDBOX/bin" "$SANDBOX/home" "$SANDBOX/app"
cp orchestrator.sh "$SANDBOX/app/"
cp -R assets "$SANDBOX/app/assets"

# mock sbatch: records argv and the full script body; returns deterministic IDs
cat > "$SANDBOX/bin/sbatch" <<'EOF'
#!/bin/bash
counter="$MOCK_DIR/counter"
n=1000
[[ -f "$counter" ]] && n=$(cat "$counter")
n=$(( n + 1 ))
echo "$n" > "$counter"
{
  echo "=== sbatch argv: $*"
  if [[ -f "$1" ]]; then
    cat "$1"
    echo "---end-script---"
  fi
} >> "$MOCK_DIR/sbatch-record"
echo "$n"
EOF

# mock component interface: mimics datatool/gistool
cat > "$SANDBOX/bin/mock-interface" <<'EOF'
#!/bin/bash
counter="$MOCK_DIR/counter"
n=1000
[[ -f "$counter" ]] && n=$(cat "$counter")
n=$(( n + 1 ))
echo "$n" > "$counter"
dep=""
for a in "$@"; do
  case "$a" in
    --dependency=*) dep="${a#--dependency=}" ;;
  esac
done
if [[ -n "$dep" ]]; then
  echo "dependency=${dep} rendered=afterok:${dep}" >> "$MOCK_DIR/interface-record"
else
  echo "dependency=none" >> "$MOCK_DIR/interface-record"
fi
echo "interface argv: $*" >> "$MOCK_DIR/interface-record"
echo "$n"
EOF
chmod +x "$SANDBOX/bin/sbatch" "$SANDBOX/bin/mock-interface"

printf '#!/bin/bash\n#SBATCH --job-name=test\n' > "$SANDBOX/tpl.slurm"

cat > "$SANDBOX/config-linear.json" <<EOF
{
  "exec": {"a": "$SANDBOX/bin/mock-interface", "b": "$SANDBOX/bin/mock-interface", "c": "$SANDBOX/bin/mock-interface"},
  "args": {"a": [{}], "b": [{}, {}], "c": [{}]},
  "order": {"a": 1, "b": 2, "c": 3},
  "submission": {"a": "", "b": "", "c": ""}
}
EOF

cat > "$SANDBOX/config-template.json" <<EOF
{
  "exec": {"x": "$SANDBOX/bin/mock-interface", "y1": "$SANDBOX/bin/mock-interface", "y2": "$SANDBOX/bin/mock-interface", "z": "$SANDBOX/bin/mock-interface"},
  "args": {"x": [{}], "y1": [{}], "y2": [{}], "z": [{}]},
  "order": {"x": -1, "y1": 1, "y2": 1, "z": 2},
  "submission": {"x": "$SANDBOX/tpl.slurm", "y1": "$SANDBOX/tpl.slurm", "y2": "$SANDBOX/tpl.slurm", "z": "$SANDBOX/tpl.slurm"}
}
EOF

run_test () {
  rm -f "$SANDBOX/counter" "$SANDBOX/sbatch-record" "$SANDBOX/interface-record"
  rm -f "$SANDBOX/app"/orchestrator_*.log
  MOCK_DIR="$SANDBOX" PATH="$SANDBOX/bin:$PATH" HOME="$SANDBOX/home" \
    bash "$SANDBOX/app/orchestrator.sh" "$1"
}
```

### A1 — interface path: level 1, two invocations at level 2, multi-parent at level 3

```bash
run_test "$SANDBOX/config-linear.json"
cat "$SANDBOX/interface-record"
# expected sequence:
#   dependency=none                                     (a)
#   dependency=1001 rendered=afterok:1001               (b, invocation 1)
#   dependency=1001 rendered=afterok:1001               (b, invocation 2, same parent)
#   dependency=1002:1003 rendered=afterok:1002:1003     (c, colon-joined parents)
grep -q "rendered=afterok:1002:1003" "$SANDBOX/interface-record" \
  && echo "A1 PASS" || echo "A1 FAIL"
```

### A2 — template path: independent process, sibling level, multi-parent

```bash
run_test "$SANDBOX/config-template.json"
grep -c "SBATCH --dependency=" "$SANDBOX/sbatch-record"   # expected: 1 (only z)
grep -q "SBATCH --dependency=afterok:1002:1003" "$SANDBOX/sbatch-record" \
  && echo "A2 PASS" || echo "A2 FAIL"
grep -q "afterok:1001" "$SANDBOX/sbatch-record" \
  && echo "A2 FAIL (independent chained)" || echo "A2 PASS (independent not chained)"
grep -q "level=-1" "$SANDBOX/app"/orchestrator_*.log \
  && echo "A2 PASS (level=-1 logged)" || echo "A2 FAIL (no level=-1)"
grep -E "afterok:[0-9]+," "$SANDBOX/sbatch-record" "$SANDBOX/interface-record" \
  > /dev/null 2>&1 && echo "A2 FAIL (comma form found)" || echo "A2 PASS (no comma form)"
```

### A3 — bad configurations must fail before any submission

```bash
cat > "$SANDBOX/bad-order.json" <<EOF
{"exec":{"a":"$SANDBOX/bin/mock-interface"},"args":{"a":[{}]},"order":{"a":0},"submission":{"a":""}}
EOF
cat > "$SANDBOX/bad-keys.json" <<EOF
{"exec":{"a":"$SANDBOX/bin/mock-interface","b":"$SANDBOX/bin/mock-interface"},"args":{"a":[{}],"c":[{}]},"order":{"a":1,"b":2},"submission":{"a":"","b":""}}
EOF
cat > "$SANDBOX/bad-args.json" <<EOF
{"exec":{"a":"$SANDBOX/bin/mock-interface"},"args":{"a":[null]},"order":{"a":1},"submission":{"a":""}}
EOF

for bad in bad-order bad-keys bad-args; do
  run_test "$SANDBOX/$bad.json" > /dev/null 2>&1
  echo "$bad exit=$? (expected 1)"
done
```

## Phase C — live SLURM validation (two trivial jobs, ~30 s)

This is the only way to confirm that real SLURM accepts the generated
`#SBATCH --dependency=afterok:id1:id2` directive written into a
template, and that `#SBATCH --parsable` yields a parseable job ID via
the real `sbatch`. It submits a parent job that sleeps 30 s
(`/bin/sleep 30`) and a child job (`/bin/echo world`) at the next level.
Note: `run_live` deliberately does **not** put the sandbox on `PATH`, so
the real `sbatch` is used.

```bash
cat > "$SANDBOX/live-1.slurm" <<EOF
#!/bin/bash
#SBATCH --job-name=orch-live-1
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --mem=500M
#SBATCH --output=$SANDBOX/orch-live-1-%j.out
EOF

cat > "$SANDBOX/live-2.slurm" <<EOF
#!/bin/bash
#SBATCH --job-name=orch-live-2
#SBATCH --ntasks=1
#SBATCH --time=00:02:00
#SBATCH --mem=500M
#SBATCH --output=$SANDBOX/orch-live-2-%j.out
EOF

cat > "$SANDBOX/config-live.json" <<EOF
{
  "exec": {"parent": "/bin/sleep", "child": "/bin/echo"},
  "args": {"parent": [{"_arguments": ["30"]}], "child": [{"_arguments": ["world"]}]},
  "order": {"parent": 1, "child": 2},
  "submission": {"parent": "$SANDBOX/live-1.slurm", "child": "$SANDBOX/live-2.slurm"}
}
EOF

run_live () {
  rm -f "$SANDBOX/app"/orchestrator_*.log
  HOME="$SANDBOX/home" bash "$SANDBOX/app/orchestrator.sh" "$1"
}

run_live "$SANDBOX/config-live.json"
ids=($(grep -o "job_id=[0-9]*" "$SANDBOX/app"/orchestrator_*.log | cut -d= -f2))
echo "parent=${ids[0]} child=${ids[1]}"
```

Immediately after submission, while the parent is sleeping:

```bash
squeue -j "${ids[1]}" -o "%.18i %.9T %.20r"     # child: PENDING, reason "Dependency"
scontrol show job "${ids[1]}" | grep -i dependency  # expect Dependency=afterok:${ids[0]}
```

If you miss the 30 s window, the post-hoc proof below still holds. Once
`squeue -u "$USER"` shows no jobs:

```bash
sacct -j "${ids[0]},${ids[1]}" --format=JobID%12,JobName%12,State%10,ExitCode,Start,End
# expect both COMPLETED with exit 0:0, and the child's Start >= the parent's End
cat "$SANDBOX"/orch-live-2-*.out    # expect: world
```

Acceptance for Phase C: child `PENDING/Dependency` while the parent runs
(observed or inferred), both jobs `COMPLETED`, child started only after
the parent ended, and the orchestrator reported both jobs with numeric
`job_id` values in its log.

## Phase D — back-port into the publication repository

Once Phases 0, A and C are green:

```console
cd <model-agnostic-framework-publication clone>
git checkout -b orchestrator-corrections
cp <agnostic-orchestrator clone>/orchestrator.sh          4-orchestration/orchestrator.sh
cp <agnostic-orchestrator clone>/assets/json-funcs.jq     4-orchestration/assets/json-funcs.jq
git diff --stat          # expect only these two files to change
```

Review the diff, then commit on the publication repository's branch in
its usual workflow. Do not touch its
`model-orchestration/model-orchestration.json` or its `.slurm`
templates. Because the artifacts are copied byte-for-byte, the Phase A/C
validation carries over.

## Reporting failures

If any phase fails, collect:

1. the failing command and its full output,
2. `bash --version`, `sed --version`, `jq --version`, `sbatch --version`,
3. the mock records (`$SANDBOX/sbatch-record`, `$SANDBOX/interface-record`),
4. the `event=submit` lines from
   `$SANDBOX/app/orchestrator_*.log`,
5. the sandbox path (kept until the investigation is over).

Do not patch around HPC-side environment problems without explicit
approval; the script targets GNU/Linux.

## Guardrails and deliberately unimplemented behavior

- Do not change the user-facing JSON schema.
- Do not add monitoring, retry, rebound, restart, or resume.
- Do not add arbitrary user-declared parent-child dependency edges; the
  workflow remains a layered graph over scalar `order` ranks.
- Known limitations: `order = 0` is invalid; bare command names (not
  path-like) are not preflight-checked; federated `jobid;cluster` IDs
  are accepted but untested; `parse_args` supports scalar and array
  values (no nested objects).

## Manuscript alignment

Use wording such as:

> The experiment specification serializes a user-defined, order-induced
> directed workflow. Vertices represent configured process invocations,
> and integer `order` values define a layered dependency hierarchy. The
> orchestrator realizes that hierarchy as scheduler jobs connected
> through success-conditioned dependencies.

and, where needed:

> The current prototype represents dependencies through scalar execution
> ranks rather than explicit parent-child edges; it supports ordered and
> layered workflow graphs, not yet arbitrary user-declared dependency
> graphs.

Do not claim that `afterok` guarantees that a job will run; it makes a
job eligible after all listed parents succeed.

#!/usr/bin/env bash
# Python's monotonic clock and process groups enforce a deadline shared by all workers.
exec python3 - "$0" "$@" <<'PY'
import argparse
import concurrent.futures
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import threading
import time

START = time.monotonic()
SCRIPT = Path(sys.argv[1]).resolve()
WORKSPACE = Path(os.environ.get('CODEX_PO_WORKSPACE_ROOT', SCRIPT.parents[2])).resolve()
REPOS = os.environ.get('CODEX_PO_REPOS', 'api-collection logged-app backend-php').split()
LOG_ROOT = Path(os.environ.get('PO_LOG_ROOT', SCRIPT.parent / 'logs')).resolve()
GENERATED = re.compile(r'(^|/)(package-lock\.json|composer\.lock|yarn\.lock)$|\.(png|jpe?g|gif|webp|ico|svg|woff2?|pdf)$|^src/i18n/locales/|^lang/')
QUOTA = re.compile(r'usage limit|rate.?limit|quota (?:exceeded|exhausted)|too many requests|\b429\b|insufficient_quota', re.I)
ACTIVE = set()
LOCK = threading.RLock()
OUTPUT = None


def fail(message, code=2):
    print(message, file=sys.stderr, flush=True)
    raise SystemExit(code)


def number_env(name, default, maximum):
    try:
        value = float(os.environ.get(name, default))
        if not 0 < value <= maximum:
            raise ValueError()
        return value
    except ValueError:
        fail(f'{name} must be greater than zero and at most {maximum}.')


TIMEOUT = number_env('REVIEW_TIMEOUT_SECONDS', '180', 180)
DEADLINE = START + TIMEOUT
# Five seconds at production settings; proportionate reserve for fast fake-provider tests.
WORK_END = DEADLINE - min(5, TIMEOUT / 10)


def kill_group(process):
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def terminal_exit(message, code):
    # A full stdout pipe must not prevent a deadline/cancellation exit.
    try:
        os.set_blocking(sys.stdout.fileno(), False)
        os.write(sys.stdout.fileno(), message.encode())
    except (OSError, ValueError):
        pass
    os._exit(code)


def hard_stop():
    with LOCK:
        for process in list(ACTIVE):
            kill_group(process)
    if OUTPUT:
        try:
            (OUTPUT / 'deadline.json').write_text(json.dumps({'total_seconds': time.monotonic() - START, 'status': 'TIMEOUT'}))
        except OSError:
            pass
    terminal_exit(f'\nPO review logs: {OUTPUT}\nPO review: TIMEOUT\n', 124)


watchdog = threading.Timer(max(.001, DEADLINE - time.monotonic() - .1), hard_stop)
watchdog.daemon = True
watchdog.start()


def interrupted(signum, frame):
    watchdog.cancel()
    with LOCK:
        for process in list(ACTIVE):
            kill_group(process)
    # RUNNING metadata and atomic worker results are sufficient for crash recovery.
    terminal_exit(f'PO review: INTERRUPTED (signal {signum}); reviewer process groups terminated\n', 128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def provider_quota(events, diagnostics):
    # CLI stderr is separate from source/tool output. In --json stdout, source strings
    # are encoded inside typed events and cannot masquerade as provider diagnostics.
    errors = [line for line in diagnostics.splitlines() if re.match(r'^(?:ERROR|Error):', line)]
    if errors:
        return bool(QUOTA.search(errors[-1]))
    errors = []
    for line in events.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if not isinstance(event, dict):
            continue
        if event.get('type') == 'error' and isinstance(event.get('message'), str):
            errors.append(event['message'])
        elif event.get('type') == 'turn.failed' and isinstance(event.get('error'), dict):
            errors.append(str(event['error'].get('message', '')))
    return bool(errors and QUOTA.search(errors[-1]))


def run(command, cwd=None, stdin=None, output=None, error_output=None):
    remaining = WORK_END - time.monotonic()
    if remaining <= 0:
        return 124, ''
    with LOCK:
        process = subprocess.Popen(command, cwd=cwd, stdin=subprocess.PIPE if stdin is not None else subprocess.DEVNULL,
                                   stdout=output or subprocess.PIPE, stderr=error_output or subprocess.STDOUT, start_new_session=True)
        ACTIVE.add(process)
    try:
        data, _ = process.communicate(stdin.encode() if stdin is not None else None, timeout=remaining)
        return process.returncode, data.decode(errors='replace') if data else ''
    except subprocess.TimeoutExpired:
        kill_group(process)
        data, _ = process.communicate()
        return 124, data.decode(errors='replace') if data else ''
    finally:
        # Also remove children left running by a CLI that exited early.
        kill_group(process)
        with LOCK:
            ACTIVE.discard(process)


def git(repo, *arguments, allow_failure=False):
    code, text = run(['git', '-C', str(WORKSPACE / repo), *arguments])
    if code == 124:
        fail('PO review: TIMEOUT during preparation', 124)
    if code and not allow_failure:
        fail(f'git failed for {repo}: {text.strip()}')
    return code, text


def save(path, value):
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2) + '\n')
    temporary.replace(path)


parser = argparse.ArgumentParser(description='Independent PO review; all preparation, reviews and quota fallback share a maximum 180-second deadline.')
parser.add_argument('--context-file', type=Path)
parser.add_argument('--audit-file', type=Path, help='JSON invariant evidence (5–15 invariants); see the skill')
parser.add_argument('--reviewer', choices=['codex', 'claude', 'auto'], default=os.environ.get('PO_REVIEWER', 'auto'))
parser.add_argument('--base', help='Diff against this ref; repositories without it use uncommitted changes')
parser.add_argument('--effort', choices=['low', 'medium', 'high'])
parser.add_argument('--repos', help='Comma-separated subset of configured repositories')
parser.add_argument('--session', help='Stable task ID; default is derived from workspace/repositories/branches')
parser.add_argument('--first-round-model', help='Optional measured model override for the largest first-round part only')
args = parser.parse_args(sys.argv[2:])
if args.reviewer not in ('codex', 'claude', 'auto'):
    fail('PO_REVIEWER must be codex|claude|auto')
CHUNK = int(number_env('PO_CHUNK_LINES', '400', 100000))
CONCURRENCY = int(number_env('PO_MAX_PARALLEL', '6', 6))
if not CHUNK or not CONCURRENCY:
    fail('PO_CHUNK_LINES and PO_MAX_PARALLEL must be positive integers')
selected = args.repos.split(',') if args.repos else REPOS
if not selected or any(r not in REPOS for r in selected) or len(set(selected)) != len(selected):
    fail('--repos must be a nonempty, nonduplicated subset of ' + ','.join(REPOS))
brief = ''
if args.context_file:
    try:
        brief = args.context_file.read_text()
    except OSError as exc:
        fail(f'Review context file is not readable: {exc}')
    if not brief.strip() or len(brief) > 2000:
        fail(f'Review context is {len(brief)} characters; supply a nonempty brief of at most 2000 characters. Launch guard: 1900.')
else:
    print('Warning: no review context supplied; reduced product context.', file=sys.stderr)


def safe_site(site):
    if not isinstance(site, dict) or site.get('repo') not in REPOS:
        fail('Audit sites/tests need a configured repo')
    path = Path(site.get('path', ''))
    if not str(path) or str(path) == '.' or path.is_absolute() or '..' in path.parts:
        fail('Audit paths must be repository-relative')
    if 'line' in site and (type(site['line']) is not int or site['line'] < 1):
        fail('Audit site line must be a positive integer')


audit = {'invariants': []}
if args.audit_file:
    try:
        raw = args.audit_file.read_text()
        if len(raw) > 64000:
            fail('Audit sidecar exceeds 64000 characters; keep evidence focused')
        audit = json.loads(raw)
        invariants = audit['invariants']
        if not isinstance(invariants, list) or not 5 <= len(invariants) <= 15:
            fail('Audit requires 5–15 invariants')
        ids = set()
        for item in invariants:
            if not all(item.get(k) for k in ('id', 'statement', 'search', 'evidence', 'sites', 'tests')) or item['id'] in ids:
                fail('Every invariant needs a unique id, statement, search, evidence, sites and tests')
            ids.add(item['id'])
            for site in item['sites']:
                safe_site(site)
                if 'line' not in site:
                    fail('Each audit site needs a line')
            for test in item['tests']:
                safe_site(test)
                if not test.get('name') or not test.get('result'):
                    fail('Each audit test needs its name and actual result (including not run/missing)')
    except (OSError, ValueError, KeyError, TypeError) as exc:
        fail(f'Invalid audit file: {exc}')
else:
    print('Warning: no invariant audit. The skill requires one for non-trivial logic.', file=sys.stderr)

# A missing executable is not a provider quota error.
executable = 'claude' if args.reviewer == 'claude' else 'codex'
if not shutil.which(executable):
    fail(f'{executable} CLI is required but was not found in PATH', 127)

branches = {}
for repo in REPOS:
    if not (WORKSPACE / repo).is_dir():
        continue
    code, branch = git(repo, 'symbolic-ref', '--short', '-q', 'HEAD', allow_failure=True)
    branches[repo] = branch.strip() if not code else 'detached'
session_key = args.session or json.dumps([str(WORKSPACE), branches], sort_keys=True)
session_hash = hashlib.sha256(session_key.encode()).hexdigest()[:20]
LOG_ROOT.mkdir(parents=True, exist_ok=True)
sessions = LOG_ROOT / 'sessions'
sessions.mkdir(exist_ok=True)
lock_file = (sessions / (session_hash + '.lock')).open('a')
try:
    fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    fail('This review session already has an active round')
state_path = sessions / (session_hash + '.json')
state = json.loads(state_path.read_text()) if state_path.exists() else {'session': session_key, 'rounds': [], 'open_p1': []}
def account_coverage(record):
    debt = state.setdefault('coverage_debt', {})
    directory = Path(record['output'])
    for repo in record['heads']:
        metadata_path = directory / (repo + '.files.json')
        if not metadata_path.exists():
            continue
        metadata = json.loads(metadata_path.read_text())
        prompts = list(directory.glob(repo + '.part*-prompt.md'))
        complete = bool(prompts)
        for prompt in prompts:
            result_path = directory / (prompt.name.removesuffix('-prompt.md') + '.result.json')
            result = json.loads(result_path.read_text()) if result_path.exists() else {}
            complete = complete and result.get('answer', {}).get('coverage_complete') is True
        if complete and set(debt.get(repo, {}).get('paths', [])).issubset(metadata['files']):
            debt.pop(repo, None)
        elif not complete:
            prior = debt.get(repo, {})
            debt[repo] = {'base': prior.get('base', metadata.get('debt_base') or metadata['base']),
                          'paths': sorted(set(prior.get('paths', [])) | set(metadata['files']))}
    record['coverage_accounted'] = True


for record in state['rounds']:
    if not record.get('coverage_accounted'):
        account_coverage(record)


# Older metadata cannot prove which moving HEAD created symbolic debt. Fail closed
# rather than infer an origin from later overlapping rounds and hide original changes.
for repo, debt in state.get('coverage_debt', {}).items():
    base = debt.get('base')
    if not isinstance(base, str) or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', base):
        fail(f'{repo}: legacy symbolic coverage base has no unambiguous original commit; restore the original immutable review base before retrying')


# A crash/cancellation can happen after a worker atomically saved findings but before
# aggregation. Recover those findings before any subsequent delta can approve the session.
recovered = {f['id']: f for f in state['open_p1']}
recovered_followups = {f['id']: f for f in state.get('followups', [])}
for record in state['rounds']:
    if record['status'] not in ('RUNNING', 'INTERRUPTED'):
        continue
    for result_path in Path(record['output']).glob('*.result.json'):
        result = json.loads(result_path.read_text())
        for finding in result.get('answer', {}).get('findings', []):
            finding['source_round'] = record['round']
            finding['source_log'] = str(result_path)
            target = recovered if finding['severity'] == 'P1' else recovered_followups
            target[finding['id']] = finding
    record['status'] = 'RECOVERED_INTERRUPTION'
state['open_p1'] = list(recovered.values())
state['followups'] = list(recovered_followups.values())
if state_path.exists():
    save(state_path, state)
if len(state['rounds']) >= 3:
    fail('PO review: ESCALATE — three rounds already attempted. Ask the user to choose how to handle remaining findings before starting a new session.', 3)
round_number = len(state['rounds']) + 1
if round_number > 1 and not args.base:
    fail('Fix rounds require --base <previous reviewed commit>; keep the same --session')

OUTPUT = LOG_ROOT / (datetime.datetime.now().strftime('%Y%m%d-%H%M%S') + '-' + str(os.getpid()))
OUTPUT.mkdir()
save(OUTPUT / 'audit.json', audit)
(OUTPUT / 'context.md').write_text(brief)


def is_test(path):
    return bool(re.search(r'(^|/)(tests?|__tests__)/|\.(test|spec)\.', path, re.I))


def classes(repo, path):
    return {item['id'] for item in audit['invariants'] if any(s['repo'] == repo and s['path'] == path for s in item['sites'])}


def prepare(repo):
    code, _ = git(repo, 'rev-parse', '--git-dir', allow_failure=True)
    if code:
        fail(f'{repo} is not a Git repository')
    ref = 'HEAD'
    if args.base:
        code, resolved = git(repo, 'rev-parse', '--verify', args.base + '^{commit}', allow_failure=True)
        if code:
            if round_number > 1 and any(repo in r['heads'] for r in state['rounds']):
                fail(f'{repo}: fix-round --base {args.base} is unavailable; refusing to omit committed changes')
            print(f'Warning: {repo} has no {args.base}; reviewing uncommitted changes.', file=sys.stderr)
        else:
            ref = resolved.strip()
            previous_head = next((r['heads'][repo] for r in reversed(state['rounds']) if repo in r['heads']), None)
            if round_number > 1 and previous_head and ref != previous_head:
                fail(f'{repo}: fix-round base must resolve to previous reviewed commit {previous_head}, not {args.base}')
    _, head = git(repo, 'rev-parse', 'HEAD')
    if ref == 'HEAD':
        ref = head.strip()  # Freeze uncommitted-review scope before HEAD can move.
    # Name-only -z avoids numstat rename/path quoting ambiguities; measure the actual diff.
    _, names = git(repo, 'diff', '--name-only', '--no-renames', '-z', ref, '--')
    _, untracked = git(repo, 'ls-files', '--others', '--exclude-standard', '-z')
    untracked = set(filter(None, untracked.split('\0')))
    debt = state.get('coverage_debt', {}).get(repo, {})
    paths = sorted(set(filter(None, names.split('\0'))) | untracked | set(debt.get('paths', [])))
    entries, generated = [], []
    for path in paths:
        if GENERATED.search(path):
            generated.append(path)
            continue
        if path in untracked:
            code, diff = git(repo, 'diff', '--no-index', '--', '/dev/null', path, allow_failure=True)
            if code not in (0, 1):
                fail(f'Cannot read untracked diff: {repo}/{path}')
        else:
            path_ref = debt['base'] if path in debt.get('paths', []) else ref
            _, diff = git(repo, 'diff', '--no-ext-diff', '--no-renames', path_ref, '--', path)
        size = sum(line.startswith(('+', '-')) and not line.startswith(('+++', '---')) for line in diff.splitlines())
        entries.append({'path': path, 'diff': diff, 'lines': size, 'classes': classes(repo, path), 'test': is_test(path)})
    # With audit evidence, give each class one owner across whole sibling files. This
    # avoids every file reviewer independently reopening and auditing the whole feature.
    applicable = [item for item in audit['invariants'] if any(site['repo'] == repo and site['path'] in paths for site in item['sites'])]
    bins = []
    if applicable:
        for item in applicable:
            if len(bins) < 5:
                bucket = {'entries': [], 'lines': 0, 'classes': set(), 'test': False}
                bins.append(bucket)
            else:
                bucket = min(bins, key=lambda b: b['lines'])
            bucket['classes'].add(item['id'])
            for entry in entries:
                if not entry['test'] and item['id'] in entry['classes'] and entry not in bucket['entries']:
                    bucket['entries'].append(entry)
                    bucket['lines'] += entry['lines']
        assigned = {e['path'] for b in bins for e in b['entries']}
        for entry in entries:
            if not entry['test'] and entry['path'] not in assigned:
                bucket = min(bins, key=lambda b: b['lines'])
                bucket['entries'].append(entry)
                bucket['lines'] += entry['lines']
        remaining_entries = [entry for entry in entries if entry['test']]
    else:
        remaining_entries = entries
    for entry in sorted(remaining_entries, key=lambda e: (e['test'], -e['lines'], e['path'])):
        choices = [b for b in bins if b['test'] == entry['test'] and b['lines'] + entry['lines'] <= CHUNK]
        if choices:
            bucket = max(choices, key=lambda b: (len(b['classes'] & entry['classes']), -b['lines']))
        else:
            bucket = {'entries': [], 'lines': 0, 'classes': set(), 'test': entry['test']}
            bins.append(bucket)
        bucket['entries'].append(entry)
        bucket['lines'] += entry['lines']
        bucket['classes'] |= entry['classes']
    if not bins and generated:
        bins = [{'entries': [], 'lines': 0, 'classes': set(), 'test': False}]
    save(OUTPUT / (repo + '.files.json'), {'head': head.strip(), 'base': ref, 'debt_base': debt.get('base'), 'files': paths, 'generated': generated})
    units = []
    for i, bucket in enumerate(bins, 1):
        owned = [e['path'] for e in bucket['entries']]
        related = [item for item in audit['invariants'] if item['id'] in bucket['classes']]
        if bucket['test']:
            related = [item for item in audit['invariants'] if any(s['repo'] == repo and s['path'] in owned for s in item['tests'])]
        previous = [finding for finding in state['open_p1'] if finding['repo'] == repo and
                    (any(s['path'] in owned for s in finding['instances']) or finding['class'] in [x['id'] for x in related])]
        # All unresolved findings in a repository must have an owner, even if omitted from delta.
        if i == 1 and round_number == 1:
            related += [item for item in audit['invariants'] if item not in related and not any(s['repo'] == repo and s['path'] in paths for s in item['sites'] + item['tests'])]
        if i == 1:
            previous += [f for f in state['open_p1'] if f['repo'] == repo and f not in previous]
        context, omitted, used = [], [], set(owned)
        remaining = 400
        for item in related:
            for site in item['sites'] + item['tests']:
                if site['repo'] != repo or site['path'] in used:
                    continue
                used.add(site['path'])
                source = WORKSPACE / repo / site['path']
                if not source.is_file() or not source.resolve().is_relative_to((WORKSPACE / repo).resolve()):
                    omitted.append(site['path'])
                    continue
                lines = source.read_text(errors='replace').splitlines()
                line = site.get('line', 1)
                start, end = (0, len(lines)) if len(lines) <= 100 else (max(0, line - 31), min(len(lines), line + 40))
                if end - start > remaining:
                    omitted.append(site['path'])
                    continue
                context.append(site['path'] + '\n' + '\n'.join(f'{n + 1}: {lines[n]}' for n in range(start, end)))
                remaining -= end - start
        unit = {'name': f'{repo}.part{i}', 'repo': repo, 'head': head.strip(), 'base': ref,
                'paths': owned, 'lines': bucket['lines'], 'related': related, 'previous': previous,
                'context': '\n\n'.join(context), 'omitted': omitted, 'generated': generated,
                'all_files': paths, 'diff': '\n'.join(e['diff'] for e in bucket['entries'])}
        units.append(unit)
    return units


units = []
for repo in selected:
    units.extend(prepare(repo))
if not units:
    if state['open_p1'] or state.get('coverage_debt'):
        fail('PO review: FAIL — no delta to review; unresolved P1 or unfinished repository scope remains', 1)
    print('PO review: PASS (nothing to review; no model calls)')
    raise SystemExit(0)

PROMPT = '''Act as the independent product owner and senior code reviewer. Do not modify files.
Review the supplied diff and product brief. Do not run git, reread skills/AGENTS/CLAUDE files,
or run suites, builds or servers. Read adjacent source only for concrete missing context.
Check correctness, regressions, contracts, error handling, usability and design requirements.
Perform a breadth-first sweep of ALL assigned invariant classes, then inspect sibling sites.
Your class ownership is explicit in assigned_invariant_ids. Other classes have independent owners;
do not re-audit their entire implementation. For a test part, review coverage of the assigned classes.
Do NOT stop at the first blocker. Report every instance you can substantiate within this part,
grouped by class, with repository-relative file:line and concrete input/impact. Do not invent findings.
Use stable invariant IDs as class names where applicable; otherwise name a new general bug class.
P1: wrong results or data loss on realistic inputs (including concrete user-visible regressions).
P2: wrong only on rare/exotic inputs, or a guarantee violated without user-visible harm.
P3: test/documentation gaps. A strict promise alone does not promote P2/P3 to P1.
Check each assigned invariant explicitly: confirmed, violated with sites, or unverifiable with reason.
Return invariant checks for assigned_invariant_ids, not for every item in the global checklist.
Treat implementer evidence as claims to verify. Missing tests are P3, not automatic P1.
Every part owns its listed changed files; inspect related context without reopening unrelated areas.
In fix rounds, check touched sites, prior P1 resolutions and class siblings only.
If unfinished_prior_scope is supplied, complete that previously unreviewed original scope too;
an incomplete earlier review cannot be replaced by an empty delta. Report outside-scope
findings only for concrete P1 impact. Do not repeat deferred P2/P3 unless these changes affect them.
A previous P1 may be resolved only with specific code evidence; otherwise retain it as a finding.
Finish the sweep and final answer within the remaining time. Do not spend the entire budget probing
one issue. If unable to finish, set coverage_complete=false; never assert complete coverage falsely.
Return ONLY one JSON object, no Markdown fences, matching this contract:
{"decision":"PASS|FAIL","coverage_complete":true,"summary":["up to three concise bullets"],
 "findings":[{"class":"invariant ID or class name","severity":"P1|P2|P3","impact":"concrete input and consequence",
 "instances":[{"path":"relative/file","line":1}]}],
 "invariants":[{"id":"assigned invariant ID","status":"confirmed|violated|unverifiable","evidence":"sites and reasoning"}],
 "resolved":[{"id":"previous P1 ID","evidence":"specific corrected sites and why the class is fixed"}]}
Use decision FAIL iff there is a P1 or coverage_complete is false; P2/P3 do not block.
'''

def compact_evidence(item):
    sites = {}
    for site in item['sites']:
        sites.setdefault(site['repo'] + '/' + site['path'], []).append(site['line'])
    # Preserve every site without repeating a long pathname on every matched line.
    return {'id': item['id'], 'statement': item['statement'], 'search': item['search'],
            'all_sites_by_file': sites, 'tests': item['tests'],
            'evidence': item['evidence'][:1200],
            'full_evidence_file': str(OUTPUT / 'audit.json'),
            'evidence_excerpt_omitted_chars': max(0, len(item['evidence']) - 1200)}


largest = max(units, key=lambda u: u['lines'])
for unit in units:
    unit['model'] = args.first_round_model if round_number == 1 and unit is largest else None
    prompt = PROMPT + '\n' + json.dumps({'repository': unit['repo'], 'round': round_number,
        'owned_files': unit['paths'], 'all_changed_files': unit['all_files'], 'generated_files': unit['generated'],
        'brief': brief, 'unfinished_prior_scope': state.get('coverage_debt', {}).get(unit['repo']), 'invariant_checklist': [{'id': x['id'], 'statement': x['statement']} for x in audit['invariants']],
        'assigned_invariant_ids': [x['id'] for x in unit['related']],
        'assigned_invariant_evidence': [compact_evidence(x) for x in unit['related']], 'previous_P1': unit['previous'],
        'omitted_context': unit['omitted']}, indent=2) + '\nSUPPORTING CONTEXT:\n' + unit['context'] + '\nDIFF:\n' + unit['diff']
    (OUTPUT / (unit['name'] + '-prompt.md')).write_text(prompt)
    (OUTPUT / (unit['name'] + '.diff')).write_text(unit['diff'])

round_record = {'round': round_number, 'output': str(OUTPUT), 'status': 'RUNNING',
                'heads': {u['repo']: u['head'] for u in units}, 'base': args.base}
state['rounds'].append(round_record)
save(state_path, state)  # Interrupted/model-error rounds count; preflight failures do not.
PREPARED = time.monotonic()


def parse_result(text, unit):
    # No scanning arbitrary transcript for a PASS substring.
    text = text.strip()
    if text.startswith('```') and text.endswith('```'):
        text = '\n'.join(text.splitlines()[1:-1])
    value = json.loads(text)
    if not isinstance(value, dict):
        raise ValueError('final answer must be an object')
    if type(value.get('coverage_complete')) is not bool or value.get('decision') not in ('PASS', 'FAIL'):
        raise ValueError('missing decision or coverage_complete')
    if not isinstance(value.get('summary'), list) or not 1 <= len(value['summary']) <= 3 or not all(isinstance(s, str) for s in value['summary']):
        raise ValueError('summary must have 1–3 strings')
    if not all(isinstance(value.get(k), list) for k in ('findings', 'invariants', 'resolved')):
        raise ValueError('missing findings, invariants or resolved lists')
    for finding in value['findings']:
        if not isinstance(finding, dict):
            raise ValueError('finding must be an object')
        if finding.get('severity') not in ('P1', 'P2', 'P3') or not isinstance(finding.get('class'), str) or not finding['class'].strip() or not isinstance(finding.get('impact'), str) or not finding['impact'].strip() or not finding.get('instances'):
            raise ValueError('invalid finding')
        for site in finding['instances']:
            path = Path(site['path'])
            if path.is_absolute() or '..' in path.parts or str(path) == '.' or type(site['line']) is not int or site['line'] < 1:
                raise ValueError('invalid finding site')
        finding['repo'] = unit['repo']
        finding['id'] = hashlib.sha256(json.dumps([finding['repo'], finding['class'], sorted((s['path'], s['line']) for s in finding['instances'])]).encode()).hexdigest()[:12]
    expected = {x['id'] for x in unit['related']}
    received = [x['id'] for x in value['invariants']]
    if not expected.issubset(received) or len(received) != len(set(received)) or not set(received).issubset({x['id'] for x in audit['invariants']}):
        raise ValueError('invariant checks do not match assignment')
    for item in value['invariants']:
        if not isinstance(item, dict):
            raise ValueError('invariant check must be an object')
        if item.get('status') not in ('confirmed', 'violated', 'unverifiable') or not isinstance(item.get('evidence'), str) or not item['evidence'].strip():
            raise ValueError('invalid invariant check')
    for item in value['invariants']:
        if item['status'] == 'violated' and not any(f['class'] == item['id'] for f in value['findings']):
            raise ValueError('violated invariant requires a graded finding')
    prior = {f['id'] for f in unit['previous']}
    for item in value['resolved']:
        if item.get('id') not in prior or not isinstance(item.get('evidence'), str) or not item['evidence'].strip():
            raise ValueError('invalid prior finding resolution')
    decision = 'FAIL' if not value['coverage_complete'] or any(f['severity'] == 'P1' for f in value['findings']) else 'PASS'
    if value['decision'] != decision:
        raise ValueError('decision contradicts coverage/severity')
    return value


def review(unit):
    began = time.monotonic()
    result = {'unit': unit['name'], 'repo': unit['repo'], 'lines': unit['lines'], 'classes': [x['id'] for x in unit['related']], 'model': unit['model'] or 'configured default',
              'queue_seconds': began - PREPARED, 'attempts': [], 'status': 'ERROR'}
    prompt = (OUTPUT / (unit['name'] + '-prompt.md')).read_text()
    reviewer = 'claude' if args.reviewer == 'claude' else 'codex'
    try:
        for attempt in range(2):
            if time.monotonic() >= WORK_END:
                result['status'] = 'TIMEOUT'
                break
            transcript = OUTPUT / (unit['name'] + '.' + reviewer + '.txt')
            final = OUTPUT / (unit['name'] + '.' + reviewer + '.final.json')
            if reviewer == 'codex':
                command = ['codex', '-C', str(WORKSPACE / unit['repo']), 'exec', '--sandbox', 'read-only', '--json', '-o', str(final)]
                if unit['model']:
                    command += ['-m', unit['model']]
                if args.effort:
                    command += ['-c', f'model_reasoning_effort="{args.effort}"']
                command += ['-']
            else:
                command = ['claude', '-p', '--permission-mode', 'plan']
            started = time.monotonic()
            diagnostic_path = OUTPUT / (unit['name'] + '.' + reviewer + '.stderr.txt')
            with transcript.open('wb') as output, diagnostic_path.open('wb') as diagnostics:
                code, _ = run(command, cwd=WORKSPACE / unit['repo'], stdin=prompt + f'\nRemaining review time: {max(0, int(WORK_END - started))} seconds.\n', output=output, error_output=diagnostics)
            result['attempts'].append({'reviewer': reviewer, 'seconds': time.monotonic() - started, 'exit_code': code})
            if code == 124:
                result['status'] = 'TIMEOUT'
                break
            text = transcript.read_text(errors='replace')
            if code:
                # Match diagnostic tail, not the echoed prompt or a source-code mention of quota.
                if (attempt == 0 and args.reviewer == 'auto' and reviewer == 'codex'
                    and provider_quota(text, diagnostic_path.read_text(errors='replace')) and not (final.exists() and final.read_text().strip()) and shutil.which('claude')):
                    reviewer = 'claude'
                    continue
                raise ValueError(f'{reviewer} exited {code}: {diagnostic_path.read_text(errors="replace")[-600:]} {text[-300:]}')
            answer = final.read_text() if reviewer == 'codex' else text
            result['answer'] = parse_result(answer, unit)
            result['status'] = result['answer']['decision']
            break
    except (OSError, ValueError, KeyError, TypeError) as exc:
        result['error'] = str(exc)
    result['seconds'] = time.monotonic() - began
    save(OUTPUT / (unit['name'] + '.result.json'), result)
    return result


with concurrent.futures.ThreadPoolExecutor(max_workers=CONCURRENCY) as pool:
    results = list(pool.map(review, units))
REVIEWED = time.monotonic()
findings, resolutions = {}, set()
for result in results:
    answer = result.get('answer', {})
    for finding in answer.get('findings', []):
        finding['source_round'] = round_number
        finding['source_log'] = str(OUTPUT / (result['unit'] + '.result.json'))
        old = findings.get(finding['id'])
        if old is None or finding['severity'] < old['severity']:
            findings[finding['id']] = finding
    resolutions.update(x['id'] for x in answer.get('resolved', []) if answer.get('coverage_complete'))
    print(f"PO review: {result['unit']} — {result['status']} ({result['seconds']:.1f}s, {len(result['attempts'])} calls)")
    for bullet in answer.get('summary', []):
        print('- ' + bullet)
    if result.get('error'):
        print(result['error'], file=sys.stderr)

open_p1 = {f['id']: f for f in state['open_p1'] if f['id'] not in resolutions}
open_p1.update({key: f for key, f in findings.items() if f['severity'] == 'P1'})
state['open_p1'] = list(open_p1.values())
followups = {f['id']: f for f in state.get('followups', [])}
followups.update({key: f for key, f in findings.items() if f['severity'] != 'P1'})
for key in open_p1:
    followups.pop(key, None)
state['followups'] = list(followups.values())
lines = ['# Non-blocking follow-ups', '', 'P2/P3 do not block this gate. Evidence is from the recorded review, not independently executed tests.', '']
for f in followups.values():
    lines += [f"## {f['severity']} — {f['class']} ({f['id']})", f['impact'], f"Source: round {f.get('source_round', '?')}, {f.get('source_log', 'prior session')}", *[f"- {f['repo']}/{s['path']}:{s['line']}" for s in f['instances']], '']
(OUTPUT / 'follow-ups.md').write_text('\n'.join(lines) + '\n')
save(OUTPUT / 'findings.json', list(findings.values()))
account_coverage(round_record)
status = 'TIMEOUT' if any(r['status'] == 'TIMEOUT' for r in results) else 'FAIL' if open_p1 or state.get('coverage_debt') or any(r['status'] != 'PASS' for r in results) else 'PASS'
round_record['status'] = status
save(state_path, state)
metrics = {'round': round_number, 'session': session_key, 'preparation_seconds': PREPARED - START,
           'review_seconds': REVIEWED - PREPARED, 'cleanup_seconds': time.monotonic() - REVIEWED,
           'total_seconds': time.monotonic() - START, 'model_calls': sum(len(r['attempts']) for r in results),
           'max_parallel': CONCURRENCY, 'status': status, 'parts': results}
save(OUTPUT / 'metrics.json', metrics)
print(f'Follow-ups: {OUTPUT / "follow-ups.md"}\nPO review logs: {OUTPUT}\nTotal: {metrics["total_seconds"]:.2f}s; model calls: {metrics["model_calls"]}')
print('DECISION: ' + ('PASS' if status == 'PASS' else 'FAIL'))
print('PO review: ' + status)
if round_number == 3 and status != 'PASS':
    print('PO review: ESCALATE — round cap reached. Ask the user to choose fixes, scope changes, or explicit acceptance; do not launch another round.')
sys.stdout.flush()  # Keep the watchdog armed through the last potentially blocking flush.
watchdog.cancel()
raise SystemExit(124 if status == 'TIMEOUT' else 3 if round_number == 3 and status != 'PASS' else 1 if status != 'PASS' else 0)
PY

#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/base-test.sh"

python3 - <<'PY'
import os
from pathlib import Path
import subprocess
import tempfile

source = (Path(os.environ['ROOT']) / 'migrations/1789928586.sh').read_text()
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    stub = root / 'bin'
    stub.mkdir()
    config = root / 'limine.conf'
    state = root / 'dependencies'
    calls = root / 'calls'
    script = root / 'migration'
    script.write_text(source.replace('/etc/default/limine', str(config)))
    commands = {
        'uname': 'echo "$TEST_ARCH"',
        'sudo': '[[ ${FAIL_WRITE:-0} == 0 ]] || exit 42; exec "$@"',
        'pacman': '''
case "$1" in
  -Qd) grep -Fxq "$2" "$STATE" ;;
  -D)
    [[ $2 == --asexplicit ]] || exit 99
    shift 2
    printf '%s\\n' "$*" >> "$CALLS"
    for pkg in "$@"; do
      sed -i "/^${pkg}$/d" "$STATE"
    done
    ;;
  *) exit 99 ;;
esac''',
    }
    for name, body in commands.items():
        p = stub / name
        p.write_text('#!/bin/bash\n' + body + '\n')
        p.chmod(0o755)
    env = dict(os.environ, PATH=str(stub) + ':' + os.environ['PATH'],
               TEST_ARCH='aarch64', STATE=str(state), CALLS=str(calls))

    def run(**extra):
        return subprocess.run(['bash', '-euo', 'pipefail', str(script)],
                              env=dict(env, **extra), capture_output=True, text=True)

    state.write_text('limine\nlimine-mkinitcpio-hook\nlimine-snapper-sync\nsnapper\nunrelated\n')
    calls.write_text('')
    assert run().returncode == 0 and not calls.read_text()
    print('ok - ARM without Limine configuration remains untouched')
    config.touch()
    assert run(TEST_ARCH='x86_64').returncode == 0 and not calls.read_text()
    print('ok - x86 retains its package dependency policy')
    assert run(FAIL_WRITE='1').returncode == 42 and 'snapper' in state.read_text()
    print('ok - package database write failure keeps migration pending')
    assert run().returncode == 0
    assert calls.read_text().split() == ['limine', 'limine-mkinitcpio-hook', 'limine-snapper-sync', 'snapper']
    assert state.read_text() == 'unrelated\n'
    print('ok - legacy ARM recovery stack is retained, unrelated dependencies untouched')
    calls.write_text('')
    assert run().returncode == 0 and not calls.read_text()
    print('ok - explicit and absent packages are untouched on repeat execution')
PY

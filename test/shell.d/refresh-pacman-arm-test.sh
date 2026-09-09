#!/bin/bash
set -euo pipefail
source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"
require_command python3
python3 - "$ROOT" <<'PY'
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(sys.argv[1])
with tempfile.TemporaryDirectory() as d:
    tmp = Path(d)
    stub = tmp / 'bin'
    stub.mkdir()
    etc = tmp / 'etc'
    (etc / 'pacman.d').mkdir(parents=True)
    log = tmp / 'calls'
    scripts = {
        'uname': '#!/bin/bash\necho "$TEST_ARCH"\n',
        'omarchy-hook': '#!/bin/bash\necho "hook $*" >>"$TEST_LOG"\n',
        'sudo': '''#!/usr/bin/env python3
import os,sys,subprocess
from pathlib import Path
args=sys.argv[1:]
with open(os.environ['TEST_LOG'],'a') as f: f.write('sudo '+ ' '.join(args)+'\\n')
if args[0]=='env':
    assert args == ['env','OMARCHY_UPDATE_PACMAN=1','pacman','-Syyuu','--noconfirm']
    sys.exit(int(os.environ.get('TEST_PACMAN_FAIL','0')))
assert args[0] in ('cat','cp'), args
args=[os.environ['TEST_ROOT']+a if a.startswith('/etc/') else a for a in args]
if os.environ.get('TEST_COPY_FAIL') and args[0]=='cp': sys.exit(1)
sys.exit(subprocess.call(args))
''',
    }
    for name, data in scripts.items():
        (stub / name).write_text(data)
        (stub / name).chmod(0o755)
    env = dict(os.environ, PATH=f'{stub}:'+os.environ['PATH'], OMARCHY_PATH=str(root),
               TEST_ROOT=d, TEST_LOG=str(log), TEST_ARCH='aarch64')
    original = '''[options]
Architecture = auto
SigLevel = Required DatabaseOptional
[omarchy]
SigLevel = Optional TrustAll
Server = https://pkgs.omarchy.org/stable/$arch
[core]
Server = https://arm.example/$arch/$repo
[extra]
Include = /etc/pacman.d/mirrorlist
[alarm]
Server = https://arm.example/$arch/$repo
[custom]
Server = https://custom.example/stable/$arch
'''
    def run(config=original, channel='stable', arch='aarch64', **extra):
        (etc/'pacman.conf').write_text(config)
        (etc/'pacman.d/mirrorlist').write_text('ARM mirror\n')
        log.write_text('')
        result = subprocess.run(['bash',str(root/'bin/omarchy-refresh-pacman'),channel],
                                env=dict(env,TEST_ARCH=arch,**extra),capture_output=True,text=True)
        return result, (etc/'pacman.conf').read_text(), log.read_text()
    for channel in ('stable','rc','edge'):
        result, config, calls = run(channel=channel)
        assert result.returncode == 0, result.stderr
        assert config == original.replace('org/stable/',f'org/{channel}/')
        assert (etc/'pacman.d/mirrorlist').read_text() == 'ARM mirror\n'
        assert not (etc/'pacman.d/mirrorlist.bak').exists()
        assert (etc/'pacman.conf.bak').read_text() == original
        assert calls.index('hook pre-refresh-pacman') < calls.index('sudo env')
        print(f'ok - ARM {channel} preserves base repositories, custom settings and mirrors')
    for bad in (original.replace('pkgs.omarchy.org','unknown.example'),
                original.replace('[omarchy]','[other]'),
                original.replace('[core]','Include = /another/config\n[core]')):
        result, config, calls = run(config=bad)
        assert result.returncode != 0 and config == bad
        assert 'sudo cp' not in calls and 'sudo env' not in calls
    print('ok - unknown ARM channel configurations stop before writes or upgrades')
    result, config, calls = run(channel='invalid')
    assert result.returncode != 0 and not calls and config == original
    print('ok - invalid channel stops before privileged commands')
    for channel in ('stable','rc','edge'):
        result, config, calls = run(channel=channel, arch='x86_64')
        assert result.returncode == 0, result.stderr
        assert config == (root/f'default/pacman/pacman-{channel}.conf').read_text()
        assert (etc/'pacman.d/mirrorlist').read_bytes() == (root/f'default/pacman/mirrorlist-{channel}').read_bytes()
    print('ok - x86 retains template refresh for all channels')
    result, config, calls = run(TEST_COPY_FAIL='1')
    assert result.returncode != 0 and 'sudo env' not in calls
    result, _, _ = run(TEST_PACMAN_FAIL='7')
    assert result.returncode == 7
    print('ok - copy failure stops the upgrade; pacman failure propagates')
PY

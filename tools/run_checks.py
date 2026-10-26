"""Run the isolated headless regression suites; proprietary game data is optional."""
import argparse
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
CORE = ['script_compilation', 'cache_dependencies', 'loading_cache',
        'npc_navigation_budget', 'local_simulation', 'performance_foundation']
INTEGRATION = ['asset_cache', 'continue_game', 'stage_two_missions', 'stage_three_jobs', 'volcanic_disaster', 'covert_defection']
LOCAL_MOD = ['scenery_scatter', 'scenery_sessions']


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--engine', type=Path, required=True)
    parser.add_argument('--game-folder', type=Path)
    parser.add_argument('--marine', action='store_true', help='Also verify the locally installed Marine Biome')
    parser.add_argument('--suite', action='append', choices=CORE + INTEGRATION + LOCAL_MOD)
    parser.add_argument('--timeout', type=float, default=300, help='Maximum seconds per process')
    args = parser.parse_args()
    if not args.engine.is_file(): parser.error('Engine executable does not exist')
    if args.timeout <= 0: parser.error('Timeout must be positive')
    suites = args.suite or CORE + (INTEGRATION if args.game_folder else []) + (LOCAL_MOD if args.marine else [])
    if any(s in INTEGRATION + LOCAL_MOD for s in suites):
        if not args.game_folder or not (args.game_folder / 'DATA/SCEN1.BSP').is_file():
            parser.error('Integration suites require --game-folder containing DATA/SCEN1.BSP')
    if any(s in LOCAL_MOD for s in suites) and not (ROOT / 'Mods/marine-biome/mod.json').is_file():
        parser.error('Marine suites require the local Marine Biome assets')
    run_id = time.strftime('%Y%m%d-%H%M%S') + '-' + uuid.uuid4().hex[:8]
    output = ROOT / '.local/checks' / run_id
    output.mkdir(parents=True)
    environment = os.environ.copy()
    if args.game_folder: environment['OPENSC_TEST_GAME_FOLDER'] = str(args.game_folder.resolve())
    fixture = f'res://tests/cache-runner-{run_id}-fixtures'
    failed = []
    for suite in suites:
        variants = [('cold', ['--keep-test-cache', fixture]), ('warm', ['warm', fixture])] if suite == 'asset_cache' else [('', ['--original-world'] if suite == 'scenery_scatter' else ['--with-cache'] if suite == 'continue_game' else [])]
        for variant, extra in variants:
            name = suite + ('-' + variant if variant else '')
            command = [str(args.engine.resolve()), '--headless', '--audio-driver', 'Dummy', '--path', str(ROOT / 'godot'),
                       '--script', f'res://tests/verify_{suite}.gd', '--log-file', str(output / (name + '.engine.log'))]
            if extra: command += ['--'] + extra
            try:
                result = subprocess.run(command, env=environment, capture_output=True, text=True,
                    encoding='utf-8', errors='replace', timeout=args.timeout,
                    creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0))
                log = result.stdout + result.stderr
                ok = result.returncode == 0 and not re.search(r'(?m)^(?:SCRIPT )?ERROR:', log)
            except subprocess.TimeoutExpired as error:
                log = f'Timed out after {args.timeout}s\n{error.stdout!r}\n{error.stderr!r}'
                ok = False
            (output / (name + '.log')).write_text(log, encoding='utf-8')
            print(f'{"PASS" if ok else "FAIL"} {name}', flush=True)
            if not ok: failed.append(name)
    print(f'{len(failed)} failed; logs: {output}')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())

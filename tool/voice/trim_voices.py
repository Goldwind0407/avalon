"""Turns raw recordings into the pieces the app plays.

    python tool/voice/trim_voices.py <folder>            # every persona in it
    python tool/voice/trim_voices.py <folder> --only chen

<folder> holds one sub-folder per persona (chen, yu, pei, ...) with one file
per piece, named by the script's id (v1a2b3c4d.wav / .mp3 / .flac / ...),
from whatever made them (GPT-SoVITS on Colab, edge-tts, a microphone).
Each is cut to where the speaking starts and ends (text-to-speech engines
leave a second or more of silence around every clip, which would make the
joined lines halting), made mono 24 kHz 32 kbps, and written to
assets/voice/<persona>/<id>.mp3. Files already there are skipped unless
--again is given. Needs ffmpeg (winget install Gyan.FFmpeg).
"""

import argparse
import concurrent.futures
import glob
import os
import pathlib
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets' / 'voice'
PERSONAS = ['chen', 'yu', 'pei', 'zhe', 'mia', 'kai', 'rong', 'wei', 'hu']
SOUNDS = ('.wav', '.mp3', '.flac', '.ogg', '.m4a')

# a little breath kept at each end, so joined pieces do not clip
TRIM = ('silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.04,'
        'areverse,'
        'silenceremove=start_periods=1:start_threshold=-45dB:start_silence=0.06,'
        'areverse')


def ffmpeg():
    found = shutil.which('ffmpeg')
    if found:
        return found
    # winget installs it here, and the PATH change needs a new terminal
    pattern = os.path.expandvars(
        r'%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*\ffmpeg-*\bin\ffmpeg.exe')
    found = sorted(glob.glob(pattern))
    if found:
        return found[-1]
    sys.exit('ffmpeg not found: winget install Gyan.FFmpeg')


def trim(tool, source, target):
    partial = target.with_name(target.stem + '.part.mp3')
    result = subprocess.run(
        [tool, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(source),
         '-af', TRIM, '-ac', '1', '-ar', '24000', '-b:a', '32k', str(partial)],
        capture_output=True, text=True)
    if result.returncode != 0 or not partial.exists() or partial.stat().st_size < 200:
        partial.unlink(missing_ok=True)
        return f'{source.name}: {result.stderr.strip() or "nothing left after trimming"}'
    partial.replace(target)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('folder')
    parser.add_argument('--only', help='comma-separated personas')
    parser.add_argument('--again', action='store_true', help='redo pieces already there')
    args = parser.parse_args()
    tool = ffmpeg()
    source = pathlib.Path(args.folder)
    personas = args.only.split(',') if args.only else PERSONAS
    for persona in personas:
        folder = source / persona
        if not folder.is_dir():
            continue
        target = OUT / persona
        target.mkdir(parents=True, exist_ok=True)
        jobs = []
        for path in sorted(folder.iterdir()):
            if path.suffix.lower() not in SOUNDS or not path.stem.startswith('v'):
                continue
            out = target / f'{path.stem}.mp3'
            if out.exists() and not args.again:
                continue
            jobs.append((path, out))
        print(f'{persona}: {len(jobs)} to trim')
        with concurrent.futures.ThreadPoolExecutor(os.cpu_count() or 4) as pool:
            for problem in pool.map(lambda j: trim(tool, *j), jobs):
                if problem:
                    print(f'  {persona} {problem}', file=sys.stderr)


if __name__ == '__main__':
    main()

"""Records the computer players' voices from the recording script.

    pip install edge-tts
    python tool/voice/make_voices.py                 # every voice, every piece
    python tool/voice/make_voices.py --only chen,yu  # some voices
    python tool/voice/make_voices.py --missing       # just list what is missing

Reads tool/voice/script.csv (made by test/voice_script_test.dart),
records into tool/voice/raw/<persona>/<id>.mp3 and trims each into
assets/voice/<persona>/<id>.mp3 (trim_voices.py, needs ffmpeg), skipping
what is already there, so it can be stopped and run again. The service
turns away a quick run of requests: it is slow, and better for a few
pieces than for every voice (see README.md for GPT-SoVITS on Colab). The app speaks a line only when every
piece of it is recorded in that computer's voice.

This uses edge-tts (Microsoft's online voices, free but not an official
API). To use another engine (GPT-SoVITS, Fish-Speech, Piper, ...) keep the
same file names: the script's `id` column, one folder per persona.
"""

import argparse
import asyncio
import csv
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'tool' / 'voice' / 'script.csv'
OUT = ROOT / 'assets' / 'voice'
RAW = ROOT / 'tool' / 'voice' / 'raw'

# Who sounds like whom. Three Taiwanese voices, told apart by pitch and
# pace to suit each one (lib/features/solo/persona/bot_persona.dart).
VOICES = {
    'chen': ('zh-TW-YunJheNeural', '-8Hz', '-8%'),     # 老陳: older, careful
    'yu':   ('zh-TW-HsiaoYuNeural', '+6Hz', '+10%'),   # 小魚: impulsive
    'pei':  ('zh-TW-HsiaoChenNeural', '+4Hz', '+0%'),  # 佩佩: follows others
    'zhe':  ('zh-TW-YunJheNeural', '+0Hz', '+2%'),     # 阿哲: logical
    'mia':  ('zh-TW-HsiaoChenNeural', '-4Hz', '-4%'),  # 米亞: the actor
    'kai':  ('zh-TW-YunJheNeural', '+4Hz', '+12%'),    # 阿凱: blunt
    'rong': ('zh-TW-HsiaoYuNeural', '-6Hz', '-6%'),    # 蓉蓉: few words
    'wei':  ('zh-TW-YunJheNeural', '-4Hz', '+4%'),     # 大衛: smiling
    'hu':   ('zh-TW-YunJheNeural', '+8Hz', '+8%'),     # 小虎: young, hasty
}


def pieces():
    with open(SCRIPT, encoding='utf-8') as f:
        return [(row['id'], row['text']) for row in csv.DictReader(f)]


async def record(persona, items, jobs):
    import edge_tts  # only needed when recording
    voice, pitch, rate = VOICES[persona]
    folder = RAW / persona
    folder.mkdir(parents=True, exist_ok=True)
    todo = [(i, t) for i, t in items
            if not (folder / f'{i}.mp3').exists() and not (OUT / persona / f'{i}.mp3').exists()]
    done = 0
    gate = asyncio.Semaphore(jobs)

    async def one(piece_id, text):
        nonlocal done
        target = folder / f'{piece_id}.mp3'
        partial = target.with_suffix('.part')
        async with gate:
            for attempt in range(3):
                try:
                    await edge_tts.Communicate(text, voice, pitch=pitch, rate=rate).save(str(partial))
                    partial.replace(target)
                    break
                except Exception as e:  # network hiccups: try again
                    if attempt == 2:
                        print(f'  {persona} {piece_id} {text}: {e}', file=sys.stderr)
                    await asyncio.sleep(2 * (attempt + 1))
        done += 1
        if done % 100 == 0 or done == len(todo):
            print(f'  {persona}: {done}/{len(todo)}')

    print(f'{persona}: {len(items) - len(todo)} recorded, {len(todo)} to go')
    await asyncio.gather(*(one(i, t) for i, t in todo))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--only', help='comma-separated personas')
    parser.add_argument('--jobs', type=int, default=6)
    parser.add_argument('--missing', action='store_true')
    args = parser.parse_args()
    items = pieces()
    personas = args.only.split(',') if args.only else list(VOICES)
    for persona in personas:
        if persona not in VOICES:
            sys.exit(f'unknown persona {persona}; one of {", ".join(VOICES)}')
        if args.missing:
            gone = [t for i, t in items if not (OUT / persona / f'{i}.mp3').exists()]
            print(f'{persona}: {len(gone)} of {len(items)} missing')
            continue
        asyncio.run(record(persona, items, args.jobs))
        subprocess.run([sys.executable, str(pathlib.Path(__file__).with_name('trim_voices.py')),
                        str(RAW), '--only', persona], check=False)


if __name__ == '__main__':
    main()

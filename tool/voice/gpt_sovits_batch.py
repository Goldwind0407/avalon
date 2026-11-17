"""Records every piece of the script with GPT-SoVITS, one voice per
computer player. Runs where GPT-SoVITS runs (Google Colab: see README.md
in this folder), against its api_v2 server:

    python api_v2.py -a 127.0.0.1 -p 9880 -c GPT_SoVITS/configs/tts_infer.yaml

then, from the folder holding script.csv and references/:

    python gpt_sovits_batch.py                  # every voice
    python gpt_sovits_batch.py --only chen,yu   # some voices
    python gpt_sovits_batch.py --limit 20       # a quick try first

Writes out/<persona>/<id>.wav, skipping what is already there, so it can
be stopped and run again (Colab disconnects now and then). Afterwards zip
out/, download it, and on the computer that builds the app run
tool/voice/trim_voices.py on it.
"""

import argparse
import csv
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
PERSONAS = ['chen', 'yu', 'pei', 'zhe', 'mia', 'kai', 'rong', 'wei', 'hu']


def tts(api, text, reference, prompt):
    query = urllib.parse.urlencode({
        'text': text,
        'text_lang': 'zh',
        'ref_audio_path': str(reference),
        'prompt_text': prompt,
        'prompt_lang': 'zh',
        'text_split_method': 'cut0',  # a piece is short: never split it
        'batch_size': 1,
        'media_type': 'wav',
        'streaming_mode': 'false',
    })
    with urllib.request.urlopen(f'{api}/tts?{query}', timeout=120) as response:
        return response.read()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--api', default='http://127.0.0.1:9880')
    parser.add_argument('--script', default=str(HERE / 'script.csv'))
    parser.add_argument('--references', default=str(HERE / 'references'))
    parser.add_argument('--out', default=str(HERE / 'out'))
    parser.add_argument('--only', help='comma-separated personas')
    parser.add_argument('--limit', type=int, help='at most this many pieces a voice')
    args = parser.parse_args()
    with open(args.script, encoding='utf-8') as f:
        pieces = [(row['id'], row['text']) for row in csv.DictReader(f)]
    if args.limit:
        pieces = pieces[:args.limit]
    references = pathlib.Path(args.references).resolve()
    for persona in (args.only.split(',') if args.only else PERSONAS):
        reference = references / f'{persona}.wav'
        prompt_file = references / f'{persona}.txt'
        if not reference.exists() or not prompt_file.exists():
            sys.exit(f'missing {reference} or {prompt_file} (make_references.py)')
        prompt = prompt_file.read_text(encoding='utf-8').strip()
        folder = pathlib.Path(args.out) / persona
        folder.mkdir(parents=True, exist_ok=True)
        todo = [(i, t) for i, t in pieces if not (folder / f'{i}.wav').exists()]
        print(f'{persona}: {len(pieces) - len(todo)} done, {len(todo)} to go', flush=True)
        started = time.time()
        for n, (piece_id, text) in enumerate(todo, 1):
            for attempt in range(3):
                try:
                    audio = tts(args.api, text, reference, prompt)
                    partial = folder / f'{piece_id}.part'
                    partial.write_bytes(audio)
                    partial.replace(folder / f'{piece_id}.wav')
                    break
                except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                    if attempt == 2:
                        print(f'  {persona} {piece_id} {text}: {e}', file=sys.stderr)
                    time.sleep(3)
            if n % 50 == 0 or n == len(todo):
                rate = n / (time.time() - started)
                print(f'  {persona}: {n}/{len(todo)} ({rate:.1f} a second)', flush=True)


if __name__ == '__main__':
    main()

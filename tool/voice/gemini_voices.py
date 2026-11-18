"""Speaks the computer players' lines with Gemini text-to-speech.

    setx GEMINI_API_KEY "..."     (once; then open a new terminal)

    python tool/voice/gemini_voices.py design            # make each persona's voice
    python tool/voice/gemini_voices.py design --only yu --again   # make it anew
    python tool/voice/gemini_voices.py batch             # every piece in script.csv
    python tool/voice/gemini_voices.py batch --only chen
    python tool/voice/gemini_voices.py collect           # fetch batches sent earlier
    python tool/voice/gemini_voices.py voices            # Chinese voices on offer

Each persona has a voice of its own, made from a description (DESIGNS
below) with Gemini's voice design: the Taiwanese accent and the manner
are in the voice itself. That is what lets the lines go through the Batch
API (half the price, and not held to the 100 requests a day of Tier 1),
which has no place for a direction on how to speak. The voices' ids are
kept in designed.json; `design` writes a sample of each to
tool/voice/samples/<persona>-design.wav to listen to.

`batch` sends one batch per persona, waits for it (usually minutes, at
most a day) and writes tool/voice/gemini/<persona>/<id>.wav. Pieces
already there are not sent again, and batches sent but not yet fetched
are kept in tool/voice/gemini/jobs.json for `collect`. Then

    python tool/voice/trim_voices.py tool/voice/gemini

cuts the silence and puts the pieces in assets/voice/.

The key is read from GEMINI_API_KEY and sent to Google only. These are AI
voices: say so in the app.
"""

import argparse
import array
import base64
import csv
import io
import json
import math
import os
import pathlib
import sys
import time
import urllib.error
import urllib.request
import wave

HERE = pathlib.Path(__file__).resolve().parent
HOST = 'https://generativelanguage.googleapis.com'
API = f'{HOST}/v1beta'
MODEL = os.environ.get('GEMINI_TTS_MODEL', 'gemini-3.8-flash-tts')
DESIGNED = HERE / 'designed.json'
OUT = HERE / 'gemini'
JOBS = OUT / 'jobs.json'

TAIWAN = ('speaking Taiwan Mandarin (台灣國語) with a natural Taiwanese accent, not '
          'mainland Chinese: soft retroflex sounds, light neutral tones, casual '
          'Taiwanese sentence endings like 啦、耶、喔. Sounds like chatting with '
          'friends over a board game, never like a news anchor or an audiobook.')

# persona: (gender, who they are and how they sound)
DESIGNS = {
    'chen': ('male', 'A Taiwanese man in his fifties, ' + TAIWAN + ' Low, slightly '
             'husky voice; speaks slowly and thoughtfully, pausing to weigh things '
             'before committing, like a calm uncle.'),
    'yu': ('female', 'A Taiwanese girl in her early twenties, ' + TAIWAN + ' Light, '
           'sweet, high voice; lively and quick, a little coquettish, laughs easily '
           'and does not take things too seriously.'),
    'pei': ('female', 'A Taiwanese woman around thirty, ' + TAIWAN + ' Warm, gentle '
            'medium voice; easy-going and agreeable, often goes along with others, '
            'polite and soft-spoken.'),
    'zhe': ('male', 'A Taiwanese man around thirty, an engineer type, ' + TAIWAN +
            ' Clear, even medium voice; calm and methodical, lays out facts in order '
            'as if reading data, rarely emotional.'),
    'mia': ('female', 'A young Taiwanese woman in her twenties from Taipei, ' + TAIWAN +
            ' Bright, clear voice with punch; confident and a bit playful, emotions '
            'clearly rising and falling.'),
    'kai': ('male', 'A Taiwanese man in his late twenties, ' + TAIWAN + ' Firm, '
            'slightly rough voice; blunt and impatient, says what he thinks straight '
            'out, quick and forceful.'),
    # (worded "in her forties ... soft, low, steady", the service failed on it)
    'rong': ('female', 'A Taiwanese woman around forty, ' + TAIWAN + ' Soft, calm, '
             'gentle voice; quiet and reserved, says little, speaks unhurriedly and '
             'with composure.'),
    'wei': ('male', 'A Taiwanese man in his thirties, ' + TAIWAN + ' Relaxed, smooth '
            'medium voice with a smile in it; laid-back and jokey, never in a hurry.'),
    'hu': ('male', 'A Taiwanese young man around twenty, ' + TAIWAN + ' Upbeat, '
           'youthful, slightly high voice; excitable and impulsive, easily swayed, '
           'speaks fast when worked up.'),
}
PERSONAS = list(DESIGNS)


def key():
    found = os.environ.get('GEMINI_API_KEY') or os.environ.get('GOOGLE_API_KEY')
    if not found:
        sys.exit('GEMINI_API_KEY is not set (setx GEMINI_API_KEY "...", then a new terminal)')
    return found


def request(method, path, body=None, timeout=120, raw=False, headers=None):
    url = path if path.startswith('http') else f'{API}/{path}'
    data = body if isinstance(body, bytes) else (
        None if body is None else json.dumps(body).encode())
    req = urllib.request.Request(url, method=method, data=data, headers={
        'x-goog-api-key': key(), 'Content-Type': 'application/json', **(headers or {})})
    response = urllib.request.urlopen(req, timeout=timeout)
    if raw:
        return response
    with response:
        return json.loads(response.read())


def designed():
    return json.loads(DESIGNED.read_text(encoding='utf-8')) if DESIGNED.exists() else {}


def tts_request(text, voice):
    return {
        'contents': [{'parts': [{'text': text}]}],
        'generationConfig': {
            'responseModalities': ['AUDIO'],
            'speechConfig': {'voiceConfig': {'prebuiltVoiceConfig': {'voiceName': voice}}},
        },
    }


def audio_of(response):
    """The WAV bytes in a GenerateContentResponse, or None."""
    try:
        part = response['candidates'][0]['content']['parts'][0]['inlineData']
        return base64.b64decode(part['data'])
    except (KeyError, IndexError, TypeError):
        return None


def lines_of_references():
    sys.path.insert(0, str(HERE))
    from make_references import REFERENCES
    return {p: r[3] for p, r in REFERENCES.items()}


def wait_for(name, every=30):
    while True:
        job = request('GET', name)
        state = job.get('metadata', {}).get('state')
        if state not in ('BATCH_STATE_PENDING', 'BATCH_STATE_RUNNING'):
            return job
        stats = job.get('metadata', {}).get('batchStats', {})
        print(f'  {name}: {state} {stats}', flush=True)
        time.sleep(every)


# ───────────── voices ─────────────

def design(args):
    made = designed()
    for persona in args.only or PERSONAS:
        if persona in made and not args.again:
            continue
        gender, description = DESIGNS[persona]
        voice = request('POST', 'voices', {'store': True, 'voice': {
            'model': MODEL, 'type': 'prompted', 'display_name': f'avalon-{persona}',
            'gender': gender, 'language_code': 'zh-TW',
            'prompted': {'input': description}}})
        made[persona] = {'id': voice['id'], 'description': description}
        DESIGNED.write_text(json.dumps(made, ensure_ascii=False, indent=2), encoding='utf-8')
        print(f'{persona}: {voice["id"]}')
    # a sample of each, in that persona's own line
    lines = lines_of_references()
    wanted = args.only or PERSONAS
    job = request('POST', f'models/{MODEL}:batchGenerateContent', {'batch': {
        'display_name': 'avalon-samples', 'input_config': {'requests': {'requests': [
            {'request': tts_request(lines[p], made[p]['id']), 'metadata': {'key': p}}
            for p in wanted]}}}})
    job = wait_for(job['name'], every=15)
    out = HERE / 'samples'
    out.mkdir(exist_ok=True)
    for item in job.get('response', {}).get('inlinedResponses', {}).get('inlinedResponses', []):
        persona = item['metadata']['key']
        wav = audio_of(item.get('response'))
        if wav:
            (out / f'{persona}-design.wav').write_bytes(wav)
            print(f'{persona}: samples/{persona}-design.wav')
        else:
            print(f'{persona}: no sample ({json.dumps(item)[:200]})')


def voices(_):
    page, shown = None, 0
    while True:
        answer = request('GET', 'voices' + (f'?page_token={page}' if page else ''))
        for v in answer.get('voices', []):
            if str(v.get('language_code', '')).lower().startswith(('zh', 'cmn', 'yue')):
                print(json.dumps(v, ensure_ascii=False))
                shown += 1
        page = answer.get('next_page_token')
        if not page:
            break
    print(f'{shown} voices')


# ───────────── the lines ─────────────

def upload(path):
    """Uploads [path] with the Files API; returns its name (files/...)."""
    size = path.stat().st_size
    start = request('POST', f'{HOST}/upload/v1beta/files',
                    {'file': {'display_name': path.name}}, raw=True, headers={
                        'X-Goog-Upload-Protocol': 'resumable',
                        'X-Goog-Upload-Command': 'start',
                        'X-Goog-Upload-Header-Content-Length': str(size),
                        'X-Goog-Upload-Header-Content-Type': 'application/jsonl'})
    url = start.headers['x-goog-upload-url']
    start.close()
    done = request('POST', url, path.read_bytes(), timeout=600, headers={
        'Content-Type': 'application/jsonl',
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize'})
    return done['file']['name']


def jobs():
    return json.loads(JOBS.read_text(encoding='utf-8')) if JOBS.exists() else {}


def save_jobs(kept):
    JOBS.write_text(json.dumps(kept, indent=2), encoding='utf-8')


def batch(args):
    with open(HERE / 'script.csv', encoding='utf-8') as f:
        pieces = [(row['id'], row['text']) for row in csv.DictReader(f)]
    made = designed()
    kept = jobs()
    for persona in args.only or PERSONAS:
        if persona not in made:
            sys.exit(f'{persona} has no voice yet: run `design` first')
        if any(j['persona'] == persona for j in kept.values()):
            print(f'{persona}: a batch is already out (run `collect`)')
            continue
        folder = OUT / persona
        folder.mkdir(parents=True, exist_ok=True)
        todo = [(i, t) for i, t in pieces if not (folder / f'{i}.wav').exists()]
        if args.limit:
            todo = todo[:args.limit]
        if not todo:
            print(f'{persona}: all there')
            continue
        # several pieces to a request, spoken in one take (one manner and
        # pitch for all of them), then cut apart at the pauses
        size = max(1, args.packed)
        groups = [todo[k:k + size] for k in range(0, len(todo), size)]
        lines = OUT / f'{persona}.jsonl'
        with open(lines, 'w', encoding='utf-8') as f:
            for n, group in enumerate(groups):
                f.write(json.dumps({'key': f'g{n}', 'request': tts_request(
                    '\n'.join(f'{text}。' for _, text in group), made[persona]['id'])},
                    ensure_ascii=False) + '\n')
        name = upload(lines)
        job = request('POST', f'models/{MODEL}:batchGenerateContent', {'batch': {
            'display_name': f'avalon-{persona}', 'input_config': {'file_name': name}}})
        kept[job['name']] = {'persona': persona, 'count': len(todo),
                             'groups': {f'g{n}': [i for i, _ in group]
                                        for n, group in enumerate(groups)}}
        save_jobs(kept)
        lines.unlink()
        print(f'{persona}: {len(todo)} pieces in {len(groups)} takes, sent as {job["name"]}')
    collect(args)


def cut(wav, count):
    """[wav] (one take of [count] pieces, a pause after each) cut into
    [count] WAVs at the [count] - 1 longest pauses; None when the pauses do
    not stand out clearly enough to tell where one piece ends."""
    with wave.open(io.BytesIO(wav)) as w:
        rate, width = w.getframerate(), w.getsampwidth()
        samples = array.array('h', w.readframes(w.getnframes()))
    if count == 1:
        return [wav]
    frame = int(rate * .02)
    quiet = []
    for i in range(0, len(samples) - frame, frame):
        chunk = samples[i:i + frame]
        quiet.append(math.sqrt(sum(v * v for v in chunk) / frame) < 300)
    runs, start = [], None
    for i, q in enumerate(quiet):
        if q and start is None:
            start = i
        if not q and start is not None:
            runs.append((start, i))
            start = None
    inner = sorted((r for r in runs if r[0] > 0), key=lambda r: r[1] - r[0], reverse=True)
    if len(inner) < count - 1:
        return None
    used = inner[:count - 1]
    shortest = min(b - a for a, b in used)
    following = inner[count - 1][1] - inner[count - 1][0] if len(inner) >= count else 0
    # a pause after a piece is long; one inside a piece is short
    if shortest < 15 or following > shortest * .8:
        return None
    bounds = [0] + sorted(((a + b) // 2) * frame for a, b in used) + [len(samples)]
    out = []
    for k in range(count):
        buffer = io.BytesIO()
        with wave.open(buffer, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(width)
            w.setframerate(rate)
            w.writeframes(samples[bounds[k]:bounds[k + 1]].tobytes())
        out.append(buffer.getvalue())
    return out


def collect(_):
    with open(HERE / 'script.csv', encoding='utf-8') as f:
        texts = {row['id']: row['text'] for row in csv.DictReader(f)}
    kept = jobs()
    for name, info in list(kept.items()):
        persona = info['persona']
        job = wait_for(name)
        state = job.get('metadata', {}).get('state')
        if state != 'BATCH_STATE_SUCCEEDED':
            print(f'{persona}: {state}; sent again by the next `batch`')
            del kept[name]
            save_jobs(kept)
            continue
        groups = info.get('groups')
        result = job.get('response', {}).get('responsesFile')
        written = failed = 0
        with request('GET', f'{HOST}/download/v1beta/{result}:download?alt=media',
                     raw=True, timeout=1800) as response:
            for line in response:
                if not line.strip():
                    continue
                item = json.loads(line)
                wav = audio_of(item.get('response'))
                pieces = groups[item['key']] if groups else [item['key']]
                clips = cut(wav, len(pieces)) if wav else None
                # each clip about as long as its words (a take that skipped or
                # added something does not line up)
                if clips and all(_fits(clip, texts.get(p, '')) for clip, p in zip(clips, pieces)):
                    for clip, piece in zip(clips, pieces):
                        (OUT / persona / f'{piece}.wav').write_bytes(clip)
                    written += len(pieces)
                    # which pieces came in one take (for evening takes out)
                    takes_file = OUT / persona / 'takes.json'
                    takes = json.loads(takes_file.read_text(encoding='utf-8')) \
                        if takes_file.exists() else []
                    takes.append(pieces)
                    takes_file.write_text(json.dumps(takes), encoding='utf-8')
                else:
                    failed += len(pieces)
        print(f'{persona}: {written} written, {failed} failed '
              f'(the failed are sent again by the next `batch`, in smaller takes '
              f'with --packed)')
        del kept[name]
        save_jobs(kept)


def _fits(clip, text):
    with wave.open(io.BytesIO(clip)) as w:
        seconds = w.getnframes() / w.getframerate()
    chars = max(1, len(text))
    return .25 <= seconds <= 1.6 + chars * .45


def main():
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest='command', required=True)
    d = sub.add_parser('design')
    d.add_argument('--only', nargs='*', choices=PERSONAS)
    d.add_argument('--again', action='store_true', help='make the voice anew')
    b = sub.add_parser('batch')
    b.add_argument('--only', nargs='*', choices=PERSONAS)
    b.add_argument('--limit', type=int, help='at most this many per persona')
    b.add_argument('--packed', type=int, default=16,
                   help='pieces spoken in one take (1: each on its own)')
    sub.add_parser('collect')
    sub.add_parser('voices')
    args = parser.parse_args()
    {'design': design, 'batch': batch, 'collect': collect, 'voices': voices}[args.command](args)


if __name__ == '__main__':
    main()

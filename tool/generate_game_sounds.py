"""Procedural Foley/medieval cues, overridden by matching provided MP3 sources.
Run: python tool/generate_game_sounds.py (FFmpeg needed only for MP3 imports).
"""
import math
import random
import struct
import wave
import subprocess
import shutil
import json
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parents[1] / 'assets' / 'audio'
OUT.mkdir(parents=True, exist_ok=True)
rng = random.Random(73109)
PROVIDED = OUT.parents[1] / '素材' / '音效'


def tone(freq, duration, style='bell'):
    values = []
    previous = 0.0
    for i in range(round(duration * RATE)):
        t = i / RATE
        attack = min(1, t / .008)
        if style == 'paper':
            noise = rng.uniform(-1, 1)
            v = (noise - previous) * .65
            previous = noise
            envelope = math.sin(math.pi * t / duration) ** 1.3
        elif style == 'drum':
            v = math.sin(2 * math.pi * (freq * t + 22 * .028 * (1 - math.exp(-t / .028))))
            v += rng.uniform(-1, 1) * .25 * math.exp(-t / .025)
            envelope = math.exp(-t * 16)
        elif style == 'horn':
            v = sum(math.sin(2 * math.pi * freq * k * t) / k ** 1.8 for k in range(1, 6)) * .65
            envelope = min(1, t / .06) * min(1, (duration - t) / .13)
        elif style == 'swoosh':
            v = rng.uniform(-1, 1) * .5 + math.sin(2 * math.pi * (freq * t + 180 * t * t)) * .3
            envelope = math.sin(math.pi * t / duration) ** 2
        else:
            v = (math.sin(2 * math.pi * freq * t) + .3 * math.sin(2 * math.pi * freq * 2.006 * t)
                 + .12 * math.sin(2 * math.pi * freq * 3.97 * t)) * .7
            envelope = math.exp(-t * (5 if style == 'bell' else 12))
        fade = min(1, (duration - t) / .025)
        values.append(v * envelope * attack * fade)
    return values


def cue(name, events):
    # Existing provided assets are refreshed by import_provided_sounds below.
    # Without a decoder, do not silently replace them with synthetic fallbacks.
    if (PROVIDED / f'{name}.mp3').exists() and (OUT / f'{name}.wav').exists():
        return
    length = max(start + duration for start, freq, duration, gain, style in events) + .04
    mix = [0.0] * math.ceil(length * RATE)
    for start, freq, duration, gain, style in events:
        offset = round(start * RATE)
        for i, sample in enumerate(tone(freq, duration, style)):
            mix[offset + i] += sample * gain
    peak = max(abs(v) for v in mix) or 1
    # Consistent headroom; short fades remove clicks and no cue clips.
    scale = min(.72 / peak, 1)
    pcm = b''.join(struct.pack('<h', round(max(-1, min(1, v * scale)) * 32767)) for v in mix)
    with wave.open(str(OUT / f'{name}.wav'), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(pcm)


def notes(frequencies, step=.15, length=.6, gain=.4, style='bell'):
    return [(i * step, f, length, gain, style) for i, f in enumerate(frequencies)]


cue('tap', [(0, 850, .07, .28, 'pluck')])
cue('deal', [(0, 0, .12, .28, 'paper'), (.07, 210, .09, .22, 'drum')])
cue('flip', [(0, 0, .19, .28, 'paper'), (.09, 480, .13, .14, 'pluck')])
cue('shuffle', [(i * .065, 0, .11, .20, 'paper') for i in range(7)])
cue('token', [(0, 235, .16, .48, 'drum'), (.01, 1175, .23, .16, 'bell')])
cue('seal', [(0, 130, .21, .45, 'drum'), (.04, 0, .13, .18, 'paper')])
cue('approve', notes([392, 494, 587], .09, .48, .32))
cue('reject', notes([233, 196, 147], .11, .42, .35, 'horn') + [(0, 95, .3, .4, 'drum')])
cue('questStart', notes([196, 294, 392], .15, .4, .35, 'horn'))
cue('success', notes([392, 494, 587, 784], .13, .8, .38))
cue('failure', notes([220, 196, 155.56, 110], .15, .65, .35, 'horn') + [(0, 80, .4, .45, 'drum')])
cue('turn', notes([659.25, 880], .12, .5, .3))
cue('tick', [(0, 1250, .055, .18, 'pluck')])
cue('freeDiscussion', notes([523.25, 659.25, 783.99], .12, .52, .3))
cue('assassin', [(0, 70, .5, .4, 'drum'), (.17, 110, .65, .32, 'horn'), (.32, 90, .3, .25, 'swoosh')])
cue('goodWin', notes([261.63, 329.63, 392, 523.25, 659.25, 783.99], .15, 1.0, .36, 'horn')
    + notes([1046.5, 1318.5], .34, .9, .2))
cue('evilWin', notes([146.83, 174.61, 220, 293.66], .24, 1.05, .36, 'horn')
    + [(0, 65, .5, .45, 'drum'), (.72, 73, .5, .4, 'drum')])
cue('magic', notes([523.25, 783.99, 1046.5, 783.99], .1, .7, .22))
cue('page', [(0, 0, .3, .3, 'paper')])

def import_provided_sounds():
    decoder = shutil.which('ffmpeg')
    if not decoder:
        try:
            import imageio_ffmpeg
            decoder = imageio_ffmpeg.get_ffmpeg_exe()
        except ImportError:
            print('No FFmpeg found: keeping existing provided cues. Install FFmpeg to refresh MP3 sources.')
            return
    known = {p.stem for p in OUT.glob('*.wav')}
    imported = []
    for source in sorted(PROVIDED.glob('*.mp3')):
        if source.stem not in known:
            continue
        cap = {'tap': .28, 'tick': .12, 'deal': .22, 'flip': .28,
               'token': .35, 'seal': .35, 'page': .4, 'turn': .7}.get(source.stem, 2.4)
        fade = min(.15, cap / 3)
        filters = (f'silenceremove=start_periods=1:start_duration=0.01:start_threshold=-48dB,'
                   f'atrim=duration={cap},apad=whole_dur={cap},'
                   f'afade=t=in:d=0.008,afade=t=out:st={cap - fade}:d={fade},'
                   'loudnorm=I=-20:TP=-3:LRA=7,alimiter=limit=0.72:level=false')
        target = OUT / f'{source.stem}.import.wav'
        result = subprocess.run([decoder, '-v', 'error', '-y', '-i', str(source),
            '-af', filters, '-t', str(cap), '-ac', '1', '-ar', str(RATE),
            '-map_metadata', '-1', '-fflags', '+bitexact', '-flags:a', '+bitexact',
            '-c:a', 'pcm_s16le', str(target)], capture_output=True)
        if result.returncode:
            target.unlink(missing_ok=True)
            print(f'Could not import {source.name}; keeping existing cue.')
            continue
        target.replace(OUT / f'{source.stem}.wav')
        imported.append(source.name)
    (OUT / 'provided_sources.json').write_text(json.dumps(imported, indent=2), encoding='utf-8')
    print('Imported provided MP3 cues:', ', '.join(imported))


import_provided_sounds()
print(f'Prepared {len(list(OUT.glob("*.wav")))} WAV cues in {OUT}')

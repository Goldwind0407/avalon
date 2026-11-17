"""Makes a reference voice for each computer player, for GPT-SoVITS (or
Fish-Speech) to speak like.

    pip install edge-tts
    python tool/voice/make_references.py

Writes tool/voice/references/<persona>.wav (about 6-8 seconds) and
<persona>.txt (what is said in it). A voice-cloning engine needs exactly
this pair to give every piece one persona says the same voice. These come
from edge-tts (nine requests in all); to give someone a real voice, replace
their .wav with a clean 3-10 second recording and its .txt with its words.
"""

import asyncio
import pathlib
import subprocess

from trim_voices import ffmpeg

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / 'tool' / 'voice' / 'references'

# voice, pitch, rate (as in make_voices.py), and something in character
REFERENCES = {
    'chen': ('zh-TW-YunJheNeural', '-8Hz', '-8%',
             '我想清楚了再投票。這一隊我先不表態，等大家都說完，我再決定要不要讓它過。'),
    'yu': ('zh-TW-HsiaoYuNeural', '+6Hz', '+10%',
           '哎呀，第一隊而已嘛，大家不要想太多，我覺得可以先出去看看結果再說！'),
    'pei': ('zh-TW-HsiaoChenNeural', '+4Hz', '+0%',
            '隊長說的我覺得有道理。如果大家都覺得沒問題，那這隊我也願意跟。'),
    'zhe': ('zh-TW-YunJheNeural', '+0Hz', '+2%',
            '我們看紀錄。第二次出失敗的時候，三號在隊上，而且被否決的提案裡他贊成了兩次。'),
    'mia': ('zh-TW-HsiaoChenNeural', '-4Hz', '-4%',
            '我是好人，這點我很確定。倒是剛才那張失敗牌，我想聽聽四號怎麼解釋。'),
    'kai': ('zh-TW-YunJheNeural', '+4Hz', '+12%',
            '我直接講了，五號就是很可疑。這隊有他，我反對，不用再討論了。'),
    'rong': ('zh-TW-HsiaoYuNeural', '-6Hz', '-6%',
             '我話不多。第三次那組成功了，那幾位我會比較信一點，這隊我贊成。'),
    'wei': ('zh-TW-YunJheNeural', '-4Hz', '+4%',
            '大家放輕鬆，我拿什麼牌都是好人啦。這隊我沒意見，就讓它出發吧。'),
    'hu': ('zh-TW-YunJheNeural', '+8Hz', '+8%',
           '等一下，我被說服了！二號講得對，這隊有問題，我改投反對！'),
}


async def main():
    import edge_tts
    tool = ffmpeg()
    OUT.mkdir(parents=True, exist_ok=True)
    for persona, (voice, pitch, rate, text) in REFERENCES.items():
        wav = OUT / f'{persona}.wav'
        if wav.exists():
            print(f'{persona}: already there')
            continue
        raw = OUT / f'{persona}.mp3'
        # the service turns away a quick run of requests: wait and try again
        for wait in (0, 30, 90, 240):
            await asyncio.sleep(wait)
            try:
                await edge_tts.Communicate(text, voice, pitch=pitch, rate=rate).save(str(raw))
                break
            except Exception as e:
                print(f'{persona}: {e}; trying again')
                raw.unlink(missing_ok=True)
        else:
            print(f'{persona}: gave up, run this again later')
            continue
        # trimmed, as a plain wav the engines all read
        subprocess.run([tool, '-hide_banner', '-loglevel', 'error', '-y', '-i', str(raw),
                        '-af', 'silenceremove=start_periods=1:start_threshold=-45dB,areverse,'
                               'silenceremove=start_periods=1:start_threshold=-45dB,areverse',
                        '-ac', '1', '-ar', '32000', str(wav)], check=True)
        raw.unlink()
        (OUT / f'{persona}.txt').write_text(text, encoding='utf-8')
        print(f'{persona}: done')


if __name__ == '__main__':
    asyncio.run(main())

19 個短音效：優先使用 `素材/音效/` 中與音效名稱相符的 MP3，其餘由程式原創合成。
重建：`python tool/generate_game_sounds.py`；合成僅使用 Python 標準函式庫，
匯入 MP3 需 FFmpeg（PATH 中的 `ffmpeg`，或 Python `imageio_ffmpeg`）。
原始 MP3 不修改；App 使用去除開頭靜音、音量調整並淡出的短版 WAV。
實際使用的原始 MP3 清單見 `provided_sources.json`。新增同名 MP3 後重跑即可替換。
格式：16-bit 單聲道 PCM WAV；每段不超過 3 秒，保留峰值餘裕。合成音效為 22,050 Hz；
由 MP3 匯入的音效保留原始取樣率（24–48 kHz），目前 14 個是用 Python `soundfile` 解碼轉出（未用 FFmpeg）。

| 檔名 | 用途 |
| --- | --- |
| tap | 中性選擇 |
| deal / flip / shuffle | 發牌、翻牌、洗牌 |
| token / seal | 棋子落桌、秘密卡片蓋牌提交 |
| approve / reject | 全員投完後公開提案結果 |
| questStart / success / failure | 出發、公開任務結果 |
| turn / tick / freeDiscussion | 過麥、最後五秒、自由討論開始 |
| assassin | 刺殺階段開始 |
| goodWin / evilWin | 公開陣營勝負 |
| magic | 湖中女神、王者之劍、公開陣營轉換與開場星光 |
| page | 筆記本開啟、翻頁 |

秘密身分、任務牌選擇與善惡查驗結果使用相同中性音色。
Android 使用不請求音訊焦點的 SoundPool；iOS 使用 AVAudioPlayer，
不更改 WebRTC 的音訊類別、輸出路由或啟用狀態。最多三個短音效同播，
背景／關閉音效時停止，沒有背景音樂或循環播放。

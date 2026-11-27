# 電腦玩家語音：錄製流程

電腦的台詞會在遊戲中臨時組合，所以不是錄整句，而是錄「片段」。片段是在標點和數字的位置切開的句子段落，數字連同單位另外錄，例如「3號」「第1次」。總共約 2,160 段，9 位電腦各錄一套。遊戲中依序把片段接起來唸；只要有一段沒錄到，那句就只顯示文字。

## 檔案

| 檔案 | 用途 |
|---|---|
| `script.csv` | 錄音清單：`id`（檔名）、`text`（要唸的字）、`uses`（出現次數，越常用越前面） |
| `make_references.py` | 每位電腦的參考句（`gemini_voices.py` 錄音時先念這句定調） |
| `trim_voices.py` | 把錄好的檔案剪掉頭尾靜音、壓縮，放進 `assets/voice/` |
| `make_voices.py` | 另一條路：直接用 edge-tts 錄（會被微軟限速，不建議錄全部） |
| `gemini_voices.py` | **目前使用的**：Gemini 語音設計 + 批次 API 錄全部片段 |
| `designed.json` | 9 位電腦在 Gemini 上設計好的聲音編號（屬於你的 Google 專案） |

## 錄音：Gemini 語音

現在 `assets/voice/` 裡的聲音是這樣做的。每位電腦用一段文字描述（在 `gemini_voices.py` 的 `DESIGNS`）「設計」出自己的聲音，台灣口音和個性都在聲音本身，所以可以走批次 API：半價，而且不受 Tier 1 即時呼叫一天 100 次的限制。2026-11 全部 2,161 段 × 9 人約花 3～4 美元，幾十分鐘完成。

1. 設定金鑰（一次就好，設完重開終端機）：`setx GEMINI_API_KEY "..."`
2. 設計聲音：`python tool/voice/gemini_voices.py design`。已設計過的會跳過，每人一段試聽檔在 `tool/voice/samples/<人物>-design.wav`。不滿意就改 `DESIGNS` 的描述，再加 `--only <人物> --again` 重做那一位。
3. 錄全部片段：`python tool/voice/gemini_voices.py batch`。預設每次請求念 16 段（`--packed`），開頭先念該角色的參考句再切掉（`--no-lead` 可關），同一次念的語氣和音高一致；切不準的那組會留到下一次，用 `--packed 8`、`4`、`2`、`1` 依序再跑補齊。分開生成時同一角色的音高起伏很大（小虎 3.25 半音），這樣做降到 2.80，偏離超過 4 個半音的片段從 23% 降到 13%。每位電腦送一個批次，完成後寫進 `tool/voice/gemini/<人物>/`。已經有的不會重送，中途關掉可以用 `collect` 把送出的批次抓回來。
4. 剪靜音、放進 App：`python tool/voice/trim_voices.py tool/voice/gemini`
5. 檢查有沒有念錯：偶爾會有一段念得太長（模型自己多講），把那段的 `.wav` 和 `assets/voice` 裡的 `.mp3` 移走，再跑一次 `batch` 和第 4 步，就只會補那幾段。

台詞改了以後：先重跑錄音清單（見主 README），再跑第 3、4 步，只會錄新的片段。這些是 AI 生成的聲音，App 的音效設定裡有註明。

## 檢查還缺哪些

```
python tool/voice/make_voices.py --missing
```

會列出每位電腦還缺幾段。

## 修改台詞之後

台詞庫或電腦的發言程式有改動時，要重新產生錄音清單，再補錄新出現的片段。已經錄好的片段，只要字沒變，編號就不會變，不必重錄：

```
VOICE_SCRIPT_OUT=tool/voice/script.csv VOICE_SCRIPT_GAMES=3000 flutter test test/voice_script_test.dart
```

## 大小

剪掉靜音並壓縮後，每段平均約 7 KB。9 個聲音全部錄完約 130 MB，會讓 App 變大這麼多。

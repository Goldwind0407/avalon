# 電腦玩家語音：錄製流程

電腦的台詞會在遊戲中臨時組合，所以不是錄整句，而是錄「片段」。片段是在標點和數字的位置切開的句子段落，數字連同單位另外錄，例如「3號」「第1次」。總共約 2,160 段，9 位電腦各錄一套。遊戲中依序把片段接起來唸；只要有一段沒錄到，那句就只顯示文字。

## 檔案

| 檔案 | 用途 |
|---|---|
| `script.csv` | 錄音清單：`id`（檔名）、`text`（要唸的字）、`uses`（出現次數，越常用越前面） |
| `references/<人物>.wav`、`.txt` | 每位電腦的參考聲音，約 6～8 秒，加上這段的文字 |
| `make_references.py` | 用 edge-tts 產生上面的參考聲音（只需 9 次請求） |
| `gpt_sovits_batch.py` | 在 Colab 上用 GPT-SoVITS 錄全部片段 |
| `trim_voices.py` | 把錄好的檔案剪掉頭尾靜音、壓縮，放進 `assets/voice/` |
| `make_voices.py` | 另一條路：直接用 edge-tts 錄（會被微軟限速，不建議錄全部） |

## 路線二：Google Colab + GPT-SoVITS

> 注意：這套流程我沒辦法替你在 Colab 上實際跑過。GPT-SoVITS 的安裝方式偶爾會改，遇到錯誤時，以官方說明為準。

1. **準備參考聲音**（在你的電腦上）

   ```
   pip install edge-tts
   python tool/voice/make_references.py
   ```

   會產生 `tool/voice/references/` 裡 9 組 `.wav` 和 `.txt`。如果想讓某位電腦用真人的聲音，就把他的 `.wav` 換成一段 3～10 秒、乾淨無背景音的錄音，`.txt` 換成那段錄音說的話。

2. **開啟 Colab**：到 GPT-SoVITS 的 GitHub 頁面（RVC-Boss/GPT-SoVITS），使用官方提供的 Colab 筆記本。執行時選 **T4 GPU**，依照筆記本的步驟裝好程式並下載預訓練模型。

3. **上傳檔案**：把下面幾個檔案上傳到 Colab，放在 GPT-SoVITS 資料夾旁邊的同一個資料夾，例如 `/content/voice/`：
   - `tool/voice/script.csv`
   - 整個 `tool/voice/references/` 資料夾
   - `tool/voice/gpt_sovits_batch.py`

4. **在 Colab 啟動 API**（在 GPT-SoVITS 的資料夾裡執行）：

   ```
   !nohup python api_v2.py -a 127.0.0.1 -p 9880 -c GPT_SoVITS/configs/tts_infer.yaml > api.log 2>&1 &
   ```

   等大約一分鐘，讓模型載入完成。

5. **先試 20 段**，聽聽聲音對不對：

   ```
   !cd /content/voice && python gpt_sovits_batch.py --only chen --limit 20
   ```

   產生的檔案在 `/content/voice/out/chen/`，可以下載幾個來聽。

6. **錄全部**：

   ```
   !cd /content/voice && python gpt_sovits_batch.py
   ```

   9 個聲音共約 19,500 段。已經錄好的會自動跳過，所以 Colab 斷線後重新執行同一行就能接著錄。建議每錄完一兩個聲音就先打包下載一次：

   ```
   !cd /content/voice && zip -qr out.zip out
   ```

   Colab 免費版每次使用有時間上限。中斷時重新連線，重做步驟 2～4，再執行一次步驟 6 即可。注意：Colab 斷線後，重新連線的機器是全新的，`out` 裡的檔案也會一起消失。所以每錄完一批就要下載，或在步驟 3 改把 `/content/voice/` 放在掛載的 Google Drive 裡，進度才會保留。

7. **回到你的電腦**：把 `out.zip` 解壓縮，例如解到 `C:\voice_out`，裡面會是 `out\chen\v....wav` 這樣的結構，然後執行：

   ```
   python tool/voice/trim_voices.py C:\voice_out\out
   ```

   檔案會剪掉頭尾靜音、壓縮好，放進 `assets/voice/<人物>/`。之後重新建置 App 就會唸出來。

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

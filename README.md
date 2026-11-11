# Avalon — 暗影議會

繁體中文 Flutter 阿瓦隆 App，5～10 人，兩種玩法：

- **一機遊玩**：大家在現場討論，依提示把手機交給指定玩家，秘密查看身分、投票及執行任務。
- **多機遊玩**：每人用自己的手機加入同一個房間。身分、投票和任務牌只出現在自己的手機上，由伺服器（Firebase Cloud Functions）裁決，任何手機都讀不到別人的秘密。

多機模式提供房間即時語音（LiveKit，需完成下方服務設定）；一機模式不啟動語音或要求麥克風權限。

兩種玩法共用同一個橫向遊戲桌面與動畫。

## 啟動

已包含 Android、iOS、Web 啟動專案。建議使用 Flutter 3.41 或更新的相容版本。

```sh
flutter pub get
flutter run
```

iOS 需在 macOS 使用 Xcode 建置。

## 遊玩流程

1. 首頁選擇「一機遊玩」或「多機遊玩」。
   - 一機：選擇 5～10 人並修改暱稱，直接開始。
   - 多機：輸入暱稱後建立房間，把 6 位數房號告訴其他人；其他人輸入房號加入。由房主設定角色並開始。
2. 配置角色；梅林與刺客固定加入，派西維爾、莫甘娜、莫德雷德、奧伯倫可選。其餘名額自動補忠臣與爪牙。
3. 秘密查看身分與情報（一機：依序傳遞手機；多機：各自在手機上看）。
4. 隨機決定首任隊長，隊長組隊後全員秘密投票。公布每位玩家的贊成／反對；過半贊成才通過，平票否決。
5. 任務隊員秘密出成功或失敗。正義玩家只能出成功，邪惡玩家可自由選擇。只公布總票數。
6. 正義三次任務成功後進入刺殺；刺客命中梅林則邪惡勝，否則正義勝。三次任務失敗或連續五次組隊遭否決，邪惡直接獲勝。

七人以上第四次任務需兩張失敗票才會失敗。每次否決或完成任務後由下一位玩家擔任隊長；任務獲准執行時重設連續否決次數。多機模式中，投票結果與任務結果的「繼續」由隊長按（房主也可代按）。

## 多機遊玩（Firebase）

Firebase 專案：`avalon-shadow-council`（地區 `asia-east1`）。

```
手機 ──呼叫──▶ Cloud Functions（functions/src）──寫入──▶ Firestore
  ◀──即時同步── rooms/{房號}                 公開桌面：座位、隊長、隊伍、揭曉後的票、記分
  ◀──即時同步── rooms/{房號}/private/{玩家}   只有本人能讀：自己的角色與情報
                rooms/{房號}/secret/state     任何手機都讀不到：全員角色、未揭曉的票與任務牌
```

- 手機不能直接寫入 Firestore（`firestore.rules`），所有動作都經過伺服器檢查。
- 匿名登入；同一支手機重開 App 後，用同一個房號可以回到原座位。
- 規則在兩處各有一份：`lib/features/game/game_model.dart`（一機）與 `functions/src/rules.ts`（多機）。修改規則時兩邊都要改，並同步更新兩邊的測試。

### 首次設定（只需一次）

1. Firebase Console 將專案升級為 **Blaze 方案**（Cloud Functions 需要），建議同時設定預算提醒。
2. 啟用 Firestore（地區選 `asia-east1`）與 Authentication 的「匿名」登入。
3. 部署伺服器、安全規則與自動清除設定（房間 24 小時後由 Firestore TTL 刪除）：

   ```sh
   cd functions && npm install && cd ..
   firebase deploy --only firestore,functions
   ```

> 函式需要允許公開呼叫（`invoker: 'public'`），身分由函式內的 Firebase 登入憑證檢查。若函式第一次建立失敗，之後的「更新」部署不會補上公開權限，呼叫會得到 403；此時刪除函式（`firebase functions:delete …`）再重新部署即可。

### 不連雲端，用模擬器測試

需要 Java 21。啟動模擬器後，執行 App 時指定模擬器位址：

```sh
firebase emulators:start --only auth,firestore,functions
flutter run --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2      # Android 模擬器
flutter run --dart-define=FIREBASE_EMULATOR_HOST=192.168.x.x   # 實體手機（同一個 Wi-Fi 下電腦的 IP）
```

## 多機即時語音（LiveKit）

### 服務設定

App 與 Firebase 函式已整合 LiveKit SDK；需要自行建立 LiveKit Cloud 專案並設定後，才有真正的語音通話。尚未設定時，不影響原本的多機遊戲。

1. 建立 LiveKit Cloud 專案，在專案設定取得 WebSocket URL、API Key 與 API Secret。
2. 參考 `functions/.env.example`，建立 `functions/.env.avalon-shadow-council`，只放服務網址：

   ```dotenv
   LIVEKIT_URL=wss://YOUR-PROJECT.livekit.cloud
   ```

3. 在本機終端機設定後端 Secret。依 CLI 提示輸入，勿把金鑰寫進 Flutter、Firestore 或 Git：

   ```sh
   firebase functions:secrets:set LIVEKIT_API_KEY --project avalon-shadow-council
   firebase functions:secrets:set LIVEKIT_API_SECRET --project avalon-shadow-council
   ```

4. 部署新增的語音憑證函式：

   ```sh
   cd functions
   npm install
   npm test
   cd ..
   firebase deploy --only functions:voiceToken --project avalon-shadow-council
   ```

5. 執行 `flutter pub get`，重新編譯並安裝 App（新增原生語音 SDK 與權限，不能只做 hot reload）。iOS 需在 Mac 上重新建置。

### 使用方式與權限

- 在多機大廳按「加入語音」，先以麥克風關閉的狀態聆聽；按麥克風才請求錄音權限並開始說話。加入與錄音都是玩家主動操作。
- 其他玩家須各自加入語音，才能互相聽見。大廳及座位旁顯示「說話中」。
- 大廳、對局及結算共用同一條語音連線；看秘密身分或結果動畫時仍可靜音。返回大廳不斷線，按「離開語音」或離開整個房間才結束通話。
- SDK 會嘗試自動重連；重連失敗時顯示「重試語音」，重新向 Firebase 取得憑證。
- Firebase 先驗證匿名登入及有效房間成員資格，再簽發 5 分鐘的房間限定 JWT。憑證只能發布麥克風音訊、接收其他人聲音，不能發布鏡頭、螢幕或資料訊息，也沒有管理／錄製權限。
- 語音房使用獨立 UUID，不直接使用六碼房號，避免房號日後重複而混入舊語音房。憑證只有公開暱稱與玩家 UID，不含任何角色情報。
- iOS 已加入麥克風用途說明及背景音訊宣告。Android 已加入錄音、網路與音訊權限；此版以 App 在前景遊玩為主，尚未加入 Android 背景麥克風前景服務。
- 本專案不啟用錄音或轉錄。音訊經過所設定的 LiveKit 服務傳輸。

### 驗證範圍

`flutter test` 包含控制器的權限失敗、重連狀態、離房清理、延遲連線取消，以及大廳／對局共用連線的畫面測試。`npm test` 包含實際 JWT 簽章、房間與成員限制、失效房間、音訊權限及有效期限測試。

這些自動測試使用假的音訊傳輸；在沒有 LiveKit 專案的環境下，不能驗證真正的收音、雙向聲音、耳機切換與平台背景行為。設定完成後，需用至少兩支實體手機加入同一房間測試這些項目，並確認離房後系統麥克風指示熄滅。

參考 [LiveKit Flutter 官方文件](https://docs.livekit.io/transport/sdk-platforms/flutter/) 與 [Firebase Secret 設定](https://firebase.google.com/docs/functions/config-env)。

## 隱私與限制

- 一機模式每次秘密操作都有交接遮罩；App 進入背景時重新隱藏秘密畫面。適合彼此信任的現場玩家，無防窺或截圖阻擋。
- 多機模式的秘密由伺服器保管；房主也看不到別人的身分。遊戲開始後無法加入新玩家，離開對局不會讓出座位。
- 尚未實作湖中女神等擴充規則、文字聊天或戰績。語音需設定 LiveKit 服務後使用。平台檔案使用開發用應用程式識別碼（`com.example.*`），上架前需更換並重新執行 `flutterfire configure`。

## 驗證

```sh
flutter analyze
flutter test

cd functions
npm test                # 伺服器規則（對應 game_model_test.dart）
npm run test:emulator   # 模擬器上的完整多人對局與安全規則
npm run test:cloud      # 同樣的測試，直接打已部署的正式環境（會建立並清除測試房間）
```

## 程式結構

- `lib/core/`：主題、素材路徑與共用元件。
- `lib/features/home/`：首頁與一機遊玩設定。
- `lib/features/online/`：多機遊玩的連線服務、房間大廳與連線版遊戲來源。
- `lib/features/online/voice/`：語音控制器、LiveKit 音訊傳輸、麥克風及說話狀態元件。
- `lib/features/game/game_model.dart`：一機遊玩的遊戲狀態與規則。
- `lib/features/game/game_session.dart`：遊戲桌面讀取的介面（`GameSession`），一機與多機各有實作。
- `lib/features/game/game_screen.dart`：遊戲桌面、秘密操作與揭曉畫面。
- `lib/features/table/`：桌面、卡牌、記分板與動畫元件。
- `functions/`：Cloud Functions（TypeScript）：規則、房間管理與測試。
- `firestore.rules`：Firestore 安全規則。

遊戲背景與人數可參考 [Indie Boards & Cards 官方介紹](https://indieboardsandcards.com/our-games/the-resistance-avalon/)。本專案未包含官方插畫及 Logo。

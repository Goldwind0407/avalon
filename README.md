# Avalon — 暗影議會

繁體中文 Flutter 阿瓦隆 App，5～10 人，兩種玩法：

- **一機遊玩**：大家在現場討論，依提示把手機交給指定玩家，秘密查看身分、投票及執行任務。
- **多機遊玩**：每人用自己的手機加入同一個房間。身分、投票和任務牌只出現在自己的手機上，由伺服器（Firebase Cloud Functions）裁決，任何手機都讀不到別人的秘密。

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
3. 部署伺服器與安全規則：

   ```sh
   cd functions && npm install && cd ..
   firebase deploy --only firestore,functions
   ```

4. （建議）在 Firestore 為 `rooms` 集合的 `expireAt` 欄位設定 TTL，房間會在 24 小時後自動清除。

### 不連雲端，用模擬器測試

需要 Java 21。啟動模擬器後，執行 App 時指定模擬器位址：

```sh
firebase emulators:start --only auth,firestore,functions
flutter run --dart-define=FIREBASE_EMULATOR_HOST=10.0.2.2      # Android 模擬器
flutter run --dart-define=FIREBASE_EMULATOR_HOST=192.168.x.x   # 實體手機（同一個 Wi-Fi 下電腦的 IP）
```

## 隱私與限制

- 一機模式每次秘密操作都有交接遮罩；App 進入背景時重新隱藏秘密畫面。適合彼此信任的現場玩家，無防窺或截圖阻擋。
- 多機模式的秘密由伺服器保管；房主也看不到別人的身分。遊戲開始後無法加入新玩家，離開對局不會讓出座位。
- 尚未實作湖中女神等擴充規則、聊天、語音或戰績。平台檔案使用開發用應用程式識別碼（`com.example.*`），上架前需更換並重新執行 `flutterfire configure`。

## 驗證

```sh
flutter analyze
flutter test

cd functions
npm test                # 伺服器規則（對應 game_model_test.dart）
npm run test:emulator   # 模擬器上的完整多人對局與安全規則
```

## 程式結構

- `lib/core/`：主題、素材路徑與共用元件。
- `lib/features/home/`：首頁與一機遊玩設定。
- `lib/features/online/`：多機遊玩的連線服務、房間大廳與連線版遊戲來源。
- `lib/features/game/game_model.dart`：一機遊玩的遊戲狀態與規則。
- `lib/features/game/game_session.dart`：遊戲桌面讀取的介面（`GameSession`），一機與多機各有實作。
- `lib/features/game/game_screen.dart`：遊戲桌面、秘密操作與揭曉畫面。
- `lib/features/table/`：桌面、卡牌、記分板與動畫元件。
- `functions/`：Cloud Functions（TypeScript）：規則、房間管理與測試。
- `firestore.rules`：Firestore 安全規則。

遊戲背景與人數可參考 [Indie Boards & Cards 官方介紹](https://indieboardsandcards.com/our-games/the-resistance-avalon/)。本專案未包含官方插畫及 Logo。

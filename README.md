# Avalon — 暗影議會

繁體中文 Flutter 阿瓦隆 App，5～10 人，三種玩法：

- **一機遊玩**：大家在現場討論，傳遞手機秘密查看身分及執行任務；組隊投票以公開表格一次登記每位玩家的贊成／反對。
- **多機遊玩**：每人用自己的手機加入同一個房間。身分、投票和任務牌只出現在自己的手機上，由伺服器（Firebase Cloud Functions）裁決，任何手機都讀不到別人的秘密。
- **單人練習・電腦對手**：你坐在 1 號位，其餘 4～9 位為電腦，在本機完成整場對局，不需連線或開啟麥克風。

多機模式提供房間即時語音（自建 WebRTC，跨網路時可搭配自架 TURN）；一機模式不啟動語音或要求麥克風權限。

三種玩法共用同一個橫向遊戲桌面與動畫。

## 單人練習（原型）

首頁選「單人練習・電腦對手」，設定總人數、角色與擴充後開始。沿用本機規則引擎；電腦會自行組隊、投票、執行任務、查驗、用劍與刺殺。投票和遠征結果由玩家按繼續，保留觀看動畫與推理的時間。支援湖中女神、兩種蘭斯洛特與王者之劍，也能關閉依序發言。

- 電腦僅取得自己的角色、開局可見席位、公開歷史與本人私人情報。只記得自己出過的牌，以及本人使用王者之劍看到的原始牌；其他玩家的查驗結果不會直接傳給決策引擎。公開宣稱與已驗證的私人事實分開保存。
- 決策以主觀懷疑評分、隊伍組合風險、比分與連續否決次數為依據，含少量隨機性。這些評分不是校正過的機率，尚未調整各角色勝率或加入多種難度。
- 電腦輪到發言時顯示模板字幕，約 5 秒自動換人，亦可按「下一位電腦」。真人可表達支持或換人，也可直接過麥。點標題右側對話圖示回顧公開發言；湖中女神的宣稱可能是謊言。
- 目前沒有 TTS、語音辨識或自由對話理解；真人的口頭發言不會被電腦解析。單人模式不建立 WebRTC 連線。
- 閱讀討論紀錄、筆記、規則、離開確認及 App 切到背景時暫停電腦自動操作。單人進度不保存；結束後可用相同配置重新發牌。

`test/solo_session_test.dart` 在虛擬時間下跑 674 場完整對局，涵蓋 5～10 人與可用擴充組合；另驗證基本推理、私密資訊遮蔽、模板發言與介面操作。後續應以玩家試玩與勝率分析調整策略。

## 啟動

已包含 Android、iOS、Web 啟動專案。建議使用 Flutter 3.41 或更新的相容版本。

```sh
flutter pub get
flutter run
```

iOS 需在 macOS 使用 Xcode 建置。

## 遊戲音效

首頁右上與牌桌返回鍵旁的喇叭圖示可設定音效開關與音量，會記住本機偏好。
音效與多人語音分開控制。發牌、翻牌、洗牌、組隊落子、秘密蓋牌、公開投票結果、
遠征出發／結果、過麥／最後五秒、刺殺、陣營勝利、擴充角色與筆記翻頁各有短提示。
秘密角色與選擇都使用中性聲音，通過／否決與成功／失敗只在公開動畫揭曉後播放。

音效會在退到背景、關閉音效或離開牌桌時停止；最多三個短音效同播，沒有循環背景音樂。
Android 原生 SoundPool 不請求音訊焦點；iOS AVAudioPlayer 不改動 WebRTC 音訊工作階段。
原生程式碼已更新，手機需重新編譯安裝，不能僅 hot reload；Web 支援瀏覽器播放，首次自動音效可能須先點擊畫面。
素材來源、對照表與重建方式見 `assets/audio/README.md`；`素材/音效` 的同名 MP3 會優先匯入，
其他環節使用原創合成音。原始 MP3 會保留，App 使用標準化的短版 WAV。

## 遊玩流程

1. 首頁選擇「一機遊玩」或「多機遊玩」。
   - 一機：選擇 5～10 人並修改暱稱，直接開始。
   - 多機：輸入暱稱後建立房間，把 6 位數房號告訴其他人；其他人輸入房號加入。由房主設定角色並開始。
2. 配置角色；梅林與刺客固定加入，派西維爾、莫甘娜、莫德雷德、奧伯倫可選。其餘名額自動補忠臣與爪牙。
3. 秘密查看身分與情報（一機：依序傳遞手機；多機：各自在手機上看）。
4. 隨機決定首任隊長，隊長組隊後全員投票。一機模式在公開投票表逐人登記，可先按「全員贊成／反對」再調整個別票型；確認後一次送出。多機模式仍各自秘密投票，收齊後公布。過半贊成才通過，平票否決。
5. 任務隊員秘密出成功或失敗。正義玩家只能出成功，邪惡玩家可自由選擇。只公布總票數。
6. 正義三次任務成功後進入刺殺；刺客命中梅林則邪惡勝，否則正義勝。三次任務失敗或連續五次組隊遭否決，邪惡直接獲勝。

## 玩家筆記本

筆記本提供多機與單人練習模式。在遊戲桌面標題右側點書本按鈕可開啟橫向羊皮紙筆記本，關閉後繼續原本對局；一機模式不顯示筆記本入口。

- 左頁每頁三位玩家，支援 5～10 人翻頁、文字筆記及手動 `Good`／`Evil` 標記；善惡只能擇一，再按一次可取消。點筆記內容或鉛筆即可編輯。
- 右側 1～5 頁籤切換遠征，右頁顯示已公開的隊伍、結果，以及可自行編輯的本輪筆記。點投票圖示可查看該次遠征的所有提案，包含否決的提案、隊長、隊伍、每人贊成／反對與結果。只有全員投完後才加入紀錄。
- 本人的角色、陣營、任務目標及開局可見情報會自動存入本機，不必先打開筆記本；左頁證件圖示可查看「我的開局情報」。不會讀取其他人的秘密角色，也不會在結算後以公開身分改寫原始情報。
- 每則手寫筆記最多 1,000 字，明確按「儲存」後寫入手機；取消編輯會保留原內容。清空本局筆記只清除文字與手動標記，會保留自動保存的開局情報和投票歷史。
- 私人筆記及開局情報不傳送 Firebase。公開提案由伺服器保存，手機自動備份至個人筆記本。以房間 UUID、玩家 UID 及局數區隔，同一支手機重新加入同一局可讀回；新一局使用新筆記。
- 多機語音在開關筆記本時保持連線，書頁上方保留語音操作。首次更新需要重新編譯安裝，才能載入新增的本機儲存套件。

七人以上第四次任務需兩張失敗票才會失敗。每次否決或完成任務後由下一位玩家擔任隊長；任務獲准執行時重設連續否決次數。多機模式中，投票結果與任務結果的「繼續」由隊長按（房主也可代按）。

## 發言流程（房規選項）

- 一機模式不建立語音或筆記本，預設維持自由討論；可在設定畫面右上方的計時器圖示開啟發言倒數，供現場玩家參考。
- 新版 App 建立的多機房間預設依序發言，每人 45 秒。房主可於開局前設定 30～90 秒、選隊時是否自由發言，以及投票前是否增加 60 秒自由討論。
- 選隊後從隊長下一家開始，依座位順序發言，隊長最後總結。當前玩家可提前過麥；逾時自動換人，最後自動進入投票。當前玩家高亮，倒數最後 5 秒改成紅色，輪到自己時有短提示音。
- 多機依伺服器時間和發言版本同步；重複／過期過麥不會跳過下一位。至少一支手機保持 App 運行時負責送出逾時操作，房主不在線時其他玩家也能接手。開啟筆記本不會停止倒數。
- 啟用依序發言時，僅當前發言者可開麥；關閉選隊自由討論時僅隊長可開麥。自由討論期間全員可開麥，身分／投票／任務秘密操作期間全員靜音。失去發言權會停止收音，恢復權限後仍須本人按開麥；其他手機也會停止播放沒有發言權的音軌。
- 更新後端需部署 `createRoom`、`joinRoom`、`startGame`、`move`、`setDiscussion`、`serverTime`。舊版建立的房間維持原流程；開啟依序發言前，所有玩家需更新 App 並重新加入。新版發言房間會拒絕不支援的舊版 App，避免收到無法識別的階段。

## 擴充規則（開局前選擇）

一機設定畫面與多機房間大廳左下方的「擴充規則」可加入下列擴充，多機由房主設定：

設定以三張並排卡片顯示所有開關，不需捲動；詳細說明從各卡片的「規則說明」開啟。
啟用蘭斯洛特後，角色配置會顯示正義與邪惡蘭斯洛特，兩位皆固定勾選；停用擴充才移除。
角色翻牌情報依本局配置顯示，不提示未使用的莫德雷德、莫甘娜或奧伯倫。

- **湖中女神**：開局交給第一位隊長右手邊的玩家。第 2、3、4 次任務結束後（遊戲未結束時），持有者查驗一名玩家的陣營（只看陣營，不看角色），結果只有持有者看得到；被查驗者接手湖中女神，持有過的人不能被查驗。建議 7 人以上。
- **蘭斯洛特**（7 人以上才能使用）：正義與邪惡蘭斯洛特各占一個正義、邪惡名額；兩人互不認識，邪惡蘭斯洛特會被其他壞人（與梅林）看見，但他看不到其他壞人。
  - 變體一：7 張轉換牌（5 張不變、2 張轉換）洗勻，第 3 次任務起每次任務開始前翻 1 張；翻到「轉換陣營」時兩位蘭斯洛特暗中交換陣營，出牌限制與勝負都依當下陣營。組隊被否決不會再翻牌。
  - 變體二：7 張抽 5 張，開局正面放在 5 個任務上，該任務開始時換邊。正義方蘭斯洛特只能出成功，邪惡方蘭斯洛特必須出失敗。
- **王者之劍**：隊長提案時把劍交給隊長以外的一名隊員。所有任務牌打出後、公開前，持劍者可以翻轉另一名隊員的任務牌（成功↔失敗）並看到原本的牌，也可以不使用；公開結果時所有人會知道誰翻了誰的牌。
- 規則同時寫在 `lib/features/game/game_model.dart`（一機）與 `functions/src/rules.ts`（伺服器），測試為 `test/expansion_test.dart` 與 `functions/test/expansions.test.ts`。
- 更新後端需部署 `setExpansions`、`createRoom`、`joinRoom`、`startGame`、`move`。新版 App 以 protocolVersion 3 連線；使用擴充的房間會拒絕舊版 App。

## 多機遊玩（Firebase）

Firebase 專案：`avalon-shadow-council`（地區 `asia-east1`）。

```
手機 ──呼叫──▶ Cloud Functions（functions/src）──寫入──▶ Firestore
  ◀──即時同步── rooms/{房號}                 公開桌面：座位、隊長、隊伍、揭曉後的票、記分
  ◀──即時同步── rooms/{房號}/private/{玩家}   只有本人能讀：自己的角色與情報
                rooms/{房號}/secret/state     任何手機都讀不到：全員角色、未揭曉的票與任務牌
```

- 遊戲狀態不能由手機直接寫入 Firestore（`firestore.rules`），遊戲動作都經過伺服器檢查；語音連線訊息則有獨立的成員及收件人權限。
- 匿名登入；同一支手機重開 App 後，用同一個房號可以回到原座位。
- 規則在兩處各有一份：`lib/features/game/game_model.dart`（一機）與 `functions/src/rules.ts`（多機）。修改規則時兩邊都要改，並同步更新兩邊的測試。

### 首次設定（只需一次）

1. Firebase Console 將專案升級為 **Blaze 方案**（Cloud Functions 需要），建議同時設定預算提醒。
2. 啟用 Firestore（地區選 `asia-east1`）與 Authentication 的「匿名」登入。
3. 部署伺服器、安全規則與自動清除設定（房間建立或更新狀態時續期 24 小時，到期即拒絕存取；TTL 在背景清理文件）：

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

## 多機即時語音（自建 WebRTC）

沿用手機間直連的 full-mesh 架構，使用 `flutter_webrtc`；已移除 LiveKit SDK、Token 呼叫與付費語音服務依賴。Firestore 只同步加入狀態和連線訊息，聲音不經 Firebase。**目前預設只用公開 STUN 嘗試直連，不使用 TURN，也不呼叫 `voiceIce` 取得中繼帳密。** 沒有按分鐘收費的語音 API，原本的 Firebase 用量仍可能產生費用。

### 更新與啟動

```sh
cd functions
npm install
npm test
cd ..
firebase deploy --only firestore,functions:createRoom,functions:leaveRoom --project avalon-shadow-council
flutter pub get
flutter run
```

必須部署新的安全規則、TTL 及房間函式，並建立**新房間**，舊房間沒有新的語音識別碼。直連模式不需要部署 `voiceIce` 或準備 TURN 主機／金鑰。iOS 需在 Mac 上重新編譯；原生套件更新不能只做 hot reload。不需要建立 LiveKit 帳號或填 LiveKit 金鑰。

### 先測直連

兩支手機安裝同一版 App，加入同一個新房間，兩邊各按「加入語音」。顯示 `語音 1/1 人` 代表已連上對方，再開麥測雙向聲音。輪流測「同一個 Wi-Fi」、「一支 Wi-Fi、一支行動網路」及「兩支都用行動網路」，並記錄各組合是否成功。若持續顯示 `0/1 人`，可切換網路、離開語音後重新加入；無法直連時不會自動使用任何付費中繼。最好戴耳機或分開測，避免回授影響判斷。

### 使用方式

- 僅多機模式顯示「加入語音」。加入時先聆聽，按麥克風才要求錄音權限並收音；一機模式不建立連線、不要求權限。
- 每人都要加入語音。畫面顯示實際連線數／其他已加入人數，例如 `語音 3/4 人`，以及說話提示；顯示加入成功不代表所有其他手機均已連上。
- 所有對手共用一份本機麥克風收音；關閉麥克風會停止收音軌，重新開啟時替換音軌，不必重建整個語音房。
- 大廳與對局共用通話，看秘密身分與動畫時仍能靜音。離開語音／整個房間會停止麥克風並關閉連線。
- 連線失敗會限次退避重試；持續部分無聲時，可離開語音再加入或切換網路。本輪先確認直連成功的網路組合，再決定是否需要中繼。

### 自架 coturn（跨網路時建議配置）

此節供未來需要中繼時使用；目前直連測試不需要執行。

1. 準備能從外網連到的 Linux 主機，安裝 coturn，例如 Ubuntu 的 `sudo apt install coturn`。
2. 將 `infra/voice/turnserver.conf.example` 複製成 `/etc/turnserver.conf`。修改 `realm`、外網／內網 IP（若主機在 NAT 後）及 `static-auth-secret`；用密碼產生器建立至少 32 位元組的隨機 Secret。不要把真實 Secret 寫入範例檔、Flutter 或 Git。
3. 開放主機防火牆與路由器的 `3478/UDP`、`3478/TCP`、`49160–49259/UDP`。雲端安全群組也須允許；家用網路若是 CGNAT，單靠路由器轉發無法讓外網連入。
4. 執行 `sudo systemctl enable --now coturn`；修改設定後執行 `sudo systemctl restart coturn`。
5. 複製 `functions/.env.example` 為被 Git 忽略的 `functions/.env.avalon-shadow-council`，填入：

   ```dotenv
   VOICE_TURN_URLS=turn:voice.example.com:3478?transport=udp,turn:voice.example.com:3478?transport=tcp
   VOICE_TURN_SECRET=與伺服器static-auth-secret相同的值
   ```

6. 部署 `firebase deploy --only functions:voiceIce --project avalon-shadow-council`。以 `flutter run --dart-define=VOICE_ENABLE_TURN=true`（或對應的 build 指令）重新編譯安裝，手機重新加入語音即可取得設定，不必把 TURN 密碼編進 App。未明確開啟此旗標的 App 仍只使用 STUN 直連。

`voiceIce` 只接受仍在有效房間中的玩家，透過 coturn REST HMAC 簽發四小時的短期帳密。共享 Secret 留在後端環境變數與 coturn 設定中。此版不會在通話中更新 TURN 帳密，超過四小時請重新加入語音。已有環境 Secret 管理機制時，應從該機制注入 `VOICE_TURN_SECRET`。

範例提供 UDP／TCP TURN，未包含 TLS 憑證。若要支援只允許 TLS 的網路，需為 coturn 加上有效憑證、移除 `no-tls`、開放 TLS 連接埠，再將 `turns:voice.example.com:5349?transport=tcp` 加進網址列表。這些步驟是配置範本；本次沒有替你租主機或部署 TURN。

參考 [WebRTC TURN 說明](https://webrtc.org/getting-started/turn-server)、[coturn 官方設定](https://github.com/coturn/coturn/blob/master/examples/etc/turnserver.conf) 與 [Flutter WebRTC API](https://flutter-webrtc.org/docs/flutter-webrtc/api-docs/rtc-peerconnection/)。

### 權限與驗證範圍

- 語音狀態每 30 秒更新，約 90 秒未更新就視為離線；TTL 負責最終清除，App 不等待 TTL 才關閉失聯玩家。房間重建、玩家重入及重試都有獨立識別，避免套用舊的 offer／answer／ICE 訊息。
- 安全規則只允許有效房間成員寫自己的語音狀態，發送者不能冒用 UID，連線訊息只允許接收者讀取。遊戲資料仍由 Cloud Functions 裁決，語音不交換身分或未公開投票。
- 房間與私人身分文件的伺服器讀取都要求尚未到期的有效成員；私人文件另外限制為本人 UID。後端房間操作共用到期檢查，期限缺漏或格式錯誤也拒絕操作，不以 TTL 是否已刪除作為判斷。
- 離房交易會同步刪除本人的私人身分文件與語音狀態。過期、已刪除房間或已讓出席位仍可重試清理本人的殘留資料；清理不會替過期房間續期。伺服器撤權不會回收已下載的本機筆記。
- 多機操作附上本局識別與輪次；伺服器拒絕舊局或舊輪的操作。畫面補收到跨輪更新時重設翻牌與飛行動畫，離房、撤權或對局中止時取消待執行操作並返回房間。
- 語音信令期限使用校正後的伺服器時間。同帳號在另一裝置加入時，舊裝置會關閉連線；延遲完成的開麥請求不能覆蓋之後的靜音狀態。
- 不啟用錄音或轉錄。P2P 會讓通話對方得知網路連線位址；需隱藏對方 IP 時應另做強制 TURN 模式與頻寬評估。
- iOS 已宣告麥克風用途和背景音訊；Android 已宣告錄音和網路權限。本版以 App 在前景使用為主，Android 尚無背景麥克風服務。
- `flutter test` 涵蓋 10 人的模擬握手、ICE 提早到達、重試與舊訊息隔離、離房清理、麥克風拒絕及大廳到對局共用通話。`npm test` 驗證 TURN 短期帳密；`npm run test:emulator` 驗證 Firebase 成員／訊息權限及完整遊戲。
- 自動測試不等於真實音訊驗證。仍需至少兩支實體手機測雙向聲音、拒絕麥克風後重試、關麥後系統收音指示、Wi-Fi 與行動網路互通、耳機和背景行為。十人 mesh 每支手機最多九條連線，發熱與電量必須用實機量測，再決定是否改成自架 SFU。

## 隱私與限制

- 一機模式每次秘密操作都有交接遮罩；App 進入背景時重新隱藏秘密畫面。適合彼此信任的現場玩家，無防窺或截圖阻擋。
- 多機模式的秘密由伺服器保管；房主也看不到別人的身分。遊戲開始後無法加入新玩家；暫時離開保留座位，離開房間則釋出座位，進行中的對局會中止並通知其他人。
- 尚未實作文字聊天或戰績。跨網路語音建議設定自架 TURN。平台檔案使用開發用應用程式識別碼（`com.example.*`），上架前需更換並重新執行 `flutterfire configure`。

## 驗證

```sh
flutter analyze
flutter test

cd functions
npm test                # 伺服器規則（對應 game_model_test.dart）
npm run test:emulator   # 完整多人對局、權限撤銷、到期與孤兒文件清理（到期測試僅操作模擬器）
npm run test:cloud      # 同樣的測試，直接打已部署的正式環境（會建立並清除測試房間）
```

### GitHub Actions

每次分支 push、PR 更新會執行 [Avalon CI](.github/workflows/ci.yml)。在 GitHub 的 Actions 頁面查看三項檢查：

- **Flutter tests and Web build**：靜態檢查、完整 Flutter 測試與覆蓋率、Web release 編譯。
- **Server rules and Firebase integration**：後端規則測試，以及 Auth／Firestore／Functions 模擬器的多人對局、權限與語音信令測試。
- **Android debug build**：Android APK 編譯。成功後可從該次執行的 Artifacts 下載 `avalon-android-debug`；Web 產物為 `avalon-web`，保留 7 天。

CI 固定使用 Flutter 3.41.0、Node 22、Java 21 與 Firebase CLI 15.30.0。模擬器測試使用 `demo-avalon-ci`，不需 Firebase 金鑰、不執行正式環境測試或部署。同一分支有新提交時會取消尚未結束的舊執行。

語音測試目前涵蓋模擬連線與控麥流程；CI 尚未加入實際音訊傳輸測試，也無法替代真機麥克風、耳機、背景行為與發熱驗收。Android 產物是測試用 APK；iPhone 不能安裝 APK。

## 程式結構

- `lib/core/`：主題、素材路徑與共用元件。
- `lib/features/home/`：首頁與一機遊玩設定。
- `lib/features/online/`：多機遊玩的連線服務、房間大廳與連線版遊戲來源。
- `lib/features/online/voice/`：語音控制器、WebRTC 音訊傳輸與 Firestore 連線協調、麥克風及說話狀態元件。
- `lib/features/game/game_model.dart`：一機遊玩的遊戲狀態與規則。
- `lib/features/game/game_session.dart`：遊戲桌面讀取的介面（`GameSession`），一機與多機各有實作。
- `lib/features/solo/`：本機電腦裁判、每位電腦的資訊快照、決策評分與模板發言。
- `lib/features/notebook/`：玩家／遠征筆記、本機儲存、橫向雙頁與靜態羊皮紙繪製。
- `lib/features/game/game_screen.dart`：遊戲桌面、秘密操作與揭曉畫面。
- `lib/features/table/`：桌面、卡牌、記分板與動畫元件。
- `functions/`：Cloud Functions（TypeScript）：規則、房間管理與測試。
- `firestore.rules`：Firestore 安全規則。

遊戲背景與人數可參考 [Indie Boards & Cards 官方介紹](https://indieboardsandcards.com/our-games/the-resistance-avalon/)。本專案未包含官方插畫及 Logo。

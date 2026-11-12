# 阿瓦隆單人模式：全角色台詞與觸發規格 V2.1

> 設計草案｜基準：`solo_bot_rules.md` 與 `avalon_solo_bot_v2_spec.md`｜2026-11-12
> 本資料為「可實作的台詞資料設計」，並非已修改 Dart 或驗證現有函式。所有規則變體以 `game_model.dart` 實際合法動作及資訊為準。

## 1. 角色範圍

| role ID | 角色 | 現在的陣營 | 對話目的 |
|---|---|---|---|
| `loyal_servant` | 亞瑟忠臣 | 正義 | 依公開紀錄找出可疑人，說明推理不假裝擁有私人情報 |
| `merlin` | 梅林 | 正義 | 引導組隊但不暴露只有梅林知道的線索 |
| `percival` | 派西維爾 | 正義 | 保護梅林，不洩漏候選人席位與對應關係 |
| `evil_minion` | 普通邪惡／爪牙 | 邪惡 | 建立可信度、引導失敗隊伍、必要時掩護隊友 |
| `assassin` | 刺客 | 邪惡 | 引導隊伍失敗並從公開行為推測梅林 |
| `morgana` | 莫甘娜 | 邪惡 | 藉由貌似洞悉局勢的發言誤導派西維爾和一般正義 |
| `mordred` | 莫德雷德 | 邪惡 | 利用梅林開局不識別的優勢隱蔽滲透 |
| `oberon` | 奧伯倫 | 邪惡 | 獨立破壞，不假定認識其他邪惡隊友 |
| `lancelot_good` | 目前為正義的蘭斯洛特 | 正義 | 依目前陣營判斷，尊重轉換時序與不揭露自身角色 |
| `lancelot_evil` | 目前為邪惡的蘭斯洛特 | 邪惡 | 依目前陣營誤導，遵守變體二強制失敗與情報限制 |

**涵蓋 10 種角色／狀態，105 個情境觸發群組，共 210 句模板**（每個群組至少兩句）。另外可以為每句疊加語氣個性，但不可改動事件真偽。

## 2. 來源、前提與重要限制

- 來源：使用者提供 `solo_bot_rules.md` 中的 Bot 知識限制、`speech()`、投票快取、湖中女神、蘭斯洛特兩變體、王者之劍及刺殺流程；另對照 V2 設計草案的 `DialogueAct` 架構。
- 附加核對：Dized《The Resistance: Avalon》遊戲規則指出莫甘娜會讓派西維爾看見額外的梅林候選；莫德雷德不在梅林開局可辨認邪惡中；奧伯倫不認得其他邪惡，且依該版本查驗存在特殊呈現。你的實作實際規則需以 `game_model.dart` 為準。參見 https://rules.dized.com/game/rZluqS52QmGdpoVxcmVLtg/faq 。
- `all` 代表任意角色都可以選擇，不表示所有角色在同樣局勢具有相同發言概率。
- `trigger` 與 `prerequisites` 是**人類可讀的條件規格**，尚未是可直接 Dart 執行的布林運算式；請建立對應 `DialogueContext`/`PredicateRegistry`。
- 每次發言前先計算當前陣營／角色、當前對局、合法 observation，取得已快取的投票及必要的私有記憶，再挑選可用的模板。
- 能從私人情報決定「要避開某人」不代表能公開宣稱「我知道他是邪惡」。`publicEvidenceIds` 必須能追溯；若選擇有意說謊，記錄 `claim_policy` 和謊言，不可偽造已公開的裁判事件。
- `【目標】`、`【輪次】`、`【沿用隊員】` 等是 placeholder。沒有可合法取得的欄位時，不得生成該句。
- 正義的蘭斯洛特**不能**出失敗牌；使用變體二時，當前邪惡蘭斯洛特**必須**出失敗牌（按你的 V1 文件）。兩個陣營狀態應動態切換模板集合。
- 刺殺目標、私人查驗、劍的原始牌等不應在未被允許公開時出現在文字中。派西維爾的兩名私人候選席位不應自動出現在句子中。

## 3. 台詞模板與合法性欄位

```dart
enum ClaimPolicy { publicGrounded, privateTruthClaim, privateStrategyPublicClaim, strategicOpinionBluff, explicitPrivateClaimLie }
class BotSpeechRule {
  final String id;             // e.g. RME01
  final String role;           // all / merlin / ...
  final String phase;          // discussion / assassination
  final String triggerKey;
  final List<String> prerequisites;
  final String intent;
  final int priority;
  final ClaimPolicy claimPolicy;
  final List<String> templates;
  const BotSpeechRule(...); // 按專案實際型別補完
}
```

**關鍵：**請把候選台詞「證據是否存在、是否違背目前立場、是否洩漏秘密」放在隨機抽句之前檢查。優先度僅做候選排序，不能繞過硬限制。

## 4. 共通情境發言庫

### `G01` uncertain（優先度 42）

- **觸發條件：**首次任務，沒有有效私人可公開證據
- **必要資料／限制：**無額外條件（仍須滿足角色、局勢、合法資料）
- **台詞 A：**「現在公開資訊還少，我想先看這隊的投票結果。」
- **台詞 B：**「第一場先別把任何人直接當成好人或壞人，我會看組隊理由。」
- **主張型態：**`public_grounded`

### `G02` support_team（優先度 62）

- **觸發條件：**決定投贊成，且隊伍比上一提案風險更低
- **必要資料／限制：**`cachedVote=approve`, `teamComparisonAvailable`
- **台詞 A：**「跟上一隊相比，這個組合我比較能接受，我會贊成。」
- **台詞 B：**「這隊至少有調整到我擔心的地方，我願意讓它試一次。」
- **主張型態：**`public_grounded`

### `G03` cautious_support（優先度 45）

- **觸發條件：**決定投贊成，但資訊不足
- **必要資料／限制：**`cachedVote=approve`
- **台詞 A：**「我沒有把握這隊完全安全，但現階段可以試一次。」
- **台詞 B：**「我先支持這隊，之後再用任務結果更新判斷。」
- **主張型態：**`public_grounded`

### `G04` oppose_team（優先度 72）

- **觸發條件：**決定投反對，隊中有可引用的公開疑點
- **必要資料／限制：**`cachedVote=reject`, `publicEvidenceForTarget`
- **台詞 A：**「我反對的原因是【目標】在第【輪次】次遠征後仍有疑點。」
- **台詞 B：**「我擔心這隊的【目標】；先解釋第【輪次】次任務的問題吧。」
- **主張型態：**`public_grounded`

### `G05` oppose_soft（優先度 42）

- **觸發條件：**決定投反對，缺乏可公開引用的證據
- **必要資料／限制：**`cachedVote=reject`
- **台詞 A：**「這個組合我不太放心，我希望再看一隊。」
- **台詞 B：**「現在我還不願意押這組，先換人試試。」
- **主張型態：**`public_grounded`

### `G06` fifth_vote_good（優先度 100）

- **觸發條件：**連續否決四次；正義已快取贊成票
- **必要資料／限制：**`rejections=4`, `cachedVote=approve`, `alignment=good`
- **台詞 A：**「已經否決四次，再否決就輸，這票我會贊成。」
- **台詞 B：**「第五次提案不能再否決了，先讓任務出發。」
- **主張型態：**`public_grounded`

### `G07` fifth_vote_evil_deception（優先度 95）

- **觸發條件：**連續否決四次；邪惡已快取反對票
- **必要資料／限制：**`rejections=4`, `cachedVote=reject`, `alignment=evil`
- **台詞 A：**「我還是覺得這份隊伍有問題，這票我不支持。」
- **台詞 B：**「就算局勢緊迫，我也無法認同這個組合。」
- **主張型態：**`intentional_opinion_bluff`
- **提醒：**避免以明顯作弊語氣提及否決即可讓邪惡獲勝

### `G08` leader_reuse（優先度 60）

- **觸發條件：**本人是隊長；沿用部分上一場成功隊員
- **必要資料／限制：**`isLeader`, `previousQuestExists`, `reusedMemberExists`
- **台詞 A：**「上一場的結果值得參考，所以我留下【沿用隊員】，其餘位置再觀察。」
- **台詞 B：**「我保留上一場部分人選，因為目前沒有足夠證據把他們全部換掉。」
- **主張型態：**`public_grounded`

### `G09` leader_reset（優先度 63）

- **觸發條件：**本人是隊長；前次失敗後大幅換人
- **必要資料／限制：**`isLeader`, `previousQuestFailed`, `teamChangedSubstantially`
- **台詞 A：**「上一隊有問題，這次我先換掉多數成員，改看新的組合。」
- **台詞 B：**「上一場的結果讓我不放心，我要換個方向測試。」
- **主張型態：**`public_grounded`

### `G10` single_swap_question（優先度 74）

- **觸發條件：**新隊伍只替換一位隊員
- **必要資料／限制：**`oneSeatChanged`, `publicOldAndNew`
- **台詞 A：**「這隊只把【舊隊員】換成【新隊員】，我想聽聽原因。」
- **台詞 B：**「只動了一個位置，隊長能說說這樣換的理由嗎？」
- **主張型態：**`public_grounded`

### `G11` defend_failed_quest（優先度 72）

- **觸發條件：**本人曾參與失敗遠征，但不能證明是哪個人出失敗
- **必要資料／限制：**`selfWasOnFailQuest`, `publicQuestReference`
- **台詞 A：**「我知道那次任務失敗會讓我被懷疑，但不能只靠結果認定某一個人。」
- **台詞 B：**「第【輪次】次任務的失敗值得追查，但每位隊員都得分開看證據。」
- **主張型態：**`public_grounded`

### `G12` defend_private_success（優先度 78）

- **觸發條件：**本人是正義且私下確定自己原始牌成功、未被翻轉
- **必要資料／限制：**`alignment=good`, `selfQuestOriginal=success`, `ownCardNotFlipped`
- **台詞 A：**「我當時出的確實是成功牌，但我知道這只是我的說法。」
- **台詞 B：**「我能保證自己交的是成功牌，至於其他人的牌，我沒有看到。」
- **主張型態：**`private_truth_claim`
- **提醒：**對外僅是主張，不能直接被其他 BOT 當成公認事實

### `G13` defend_evil_bluff（優先度 68）

- **觸發條件：**邪惡發言者需要替失敗任務辯護
- **必要資料／限制：**`alignment=evil`, `selfWasOnFailQuest`
- **台詞 A：**「我知道失敗隊伍會被懷疑，但請別跳過其他隊員的可能性。」
- **台詞 B：**「把問題全部推給我很容易，可是這次結果並沒有指出哪張牌是誰出的。」
- **主張型態：**`strategic_opinion_bluff`

### `G14` success_with_fail（優先度 82）

- **觸發條件：**遠征成功但有失敗牌，未受王者之劍特殊推理覆蓋
- **必要資料／限制：**`questCompleted`, `publicFailCount>0`, `publicQuestReference`
- **台詞 A：**「任務雖然成功，卻有【失敗張數】張失敗牌，不能因此直接洗白整隊。」
- **台詞 B：**「這場沒有判失敗，不代表隊上全都安全；失敗牌數還是要記。」
- **主張型態：**`public_grounded`

### `G15` clean_quest（優先度 51）

- **觸發條件：**遠征成功、零失敗牌
- **必要資料／限制：**`questCompleted`, `publicFailCount=0`
- **台詞 A：**「這隊暫時加分，但出成功牌不一定代表好人。」
- **台詞 B：**「沒有失敗牌是好消息，不過我還不會認定全員清白。」
- **主張型態：**`public_grounded`

### `G16` vote_contradiction（優先度 70）

- **觸發條件：**某玩家投票立場與前次相似提案不同
- **必要資料／限制：**`publicVoteHistory`, `similarProposal`, `publicTargetVoteChanged`
- **台詞 A：**「【目標】上次支持類似組合，這次卻反對，是哪個新線索改變你的想法？」
- **台詞 B：**「你兩次投票不一樣，我想知道中間發生了什麼變化。」
- **主張型態：**`public_grounded`

### `G17` reply_question（優先度 85）

- **觸發條件：**有人剛剛點名質問自己
- **必要資料／限制：**`publicDirectQuestionToSelf`, `publicEventReferenceOptional`
- **台詞 A：**「我願意解釋，但先把你指的那一輪說清楚。」
- **台詞 B：**「如果你指的是第【輪次】次提案，我當時在意的是隊伍組合。」
- **主張型態：**`public_grounded`

### `G18` defend_other（優先度 53）

- **觸發條件：**他人公開指控【目標】但公開證據不足
- **必要資料／限制：**`publicAccusationExists`
- **台詞 A：**「現在就鎖定【目標】太早了，我想再看別的證據。」
- **台詞 B：**「有懷疑可以，但目前這些資訊還不足以斷定是【目標】。」
- **主張型態：**`public_grounded`

### `G19` reassess（優先度 66）

- **觸發條件：**前次公開意見已被新證據削弱
- **必要資料／限制：**`speechMemory`, `publicNewContraryEvidence`
- **台詞 A：**「我先前對【目標】的判斷可能太快了，這場我要重看。」
- **台詞 B：**「新的任務結果跟我的預測不太一樣，我願意修正。」
- **主張型態：**`public_grounded`

### `G20` avoid_repeat（優先度 39）

- **觸發條件：**同一證據最近已被重複引用兩次
- **必要資料／限制：**`speechMemory`, `recentSemanticRepeat`
- **台詞 A：**「那件事大家都提過了，我想先看這份新提案有什麼差別。」
- **台詞 B：**「我們一直繞在同一個疑點上，先討論這次換了哪些人吧。」
- **主張型態：**`public_grounded`

### `G21` hedge_claim（優先度 62）

- **觸發條件：**有人要求直接保證某人好壞
- **必要資料／限制：**`publicDirectQuestionAboutTarget`
- **台詞 A：**「我只能說目前比較傾向信任他，還不到保證的程度。」
- **台詞 B：**「在沒有更直接的證據前，我不會把猜測說成確定。」
- **主張型態：**`public_grounded`

### `G22` endgame_focus（優先度 75）

- **觸發條件：**任務接近勝負關鍵
- **必要資料／限制：**`goodQuestWins=2 or evilQuestWins=2`
- **台詞 A：**「這一隊可能直接決定勝負，我希望先把人選理由講清楚。」
- **台詞 B：**「現在不能只靠感覺投票，誰有紀錄支持這個選法？」
- **主張型態：**`public_grounded`

### `G23` explain_vote_flip（優先度 73）

- **觸發條件：**之前承諾的立場與實際公開投票不同，且刻意說謊
- **必要資料／限制：**`speechMemory`, `claimVoteMismatch`, `bluffWasExplicitlyPlanned`
- **台詞 A：**「我當時說的是初步傾向，投票前我重新看了隊伍。」
- **台詞 B：**「我承認我後來改變立場，下次會更明確說清楚。」
- **主張型態：**`strategic_opinion_bluff`

### `G24` leader_repeat_failed（優先度 70）

- **觸發條件：**隊長選到與其上一場相同的可疑組合
- **必要資料／限制：**`publicPriorQuestReference`, `teamOverlapHigh`
- **台詞 A：**「第【輪次】次遠征用過很接近的隊伍，我希望這次給出不同理由。」
- **台詞 B：**「之前這個組合留下疑點，隊長為什麼還想再試？」
- **主張型態：**`public_grounded`

### `XLD01` lady_true_good（優先度 92）

- **觸發條件：**本人持有女神且查驗到正義，決定誠實公開
- **必要資料／限制：**`selfLadyInspected`, `inspectedValue=good`, `publicClaimMode=truth`
- **台詞 A：**「我查驗【目標】號時，結果顯示為正義陣營。」
- **台詞 B：**「我這次查到的是正義，但這只代表查驗當時的結果。」
- **主張型態：**`private_truth_claim`
- **提醒：**如奧伯倫等變體有特殊顯示，使用規則引擎提供的觀測值，不擅自替換為真實陣營

### `XLD02` lady_true_evil（優先度 94）

- **觸發條件：**本人持有女神且查驗到邪惡，決定誠實公開
- **必要資料／限制：**`selfLadyInspected`, `inspectedValue=evil`, `publicClaimMode=truth`
- **台詞 A：**「我查驗【目標】號的結果顯示邪惡，大家可以把這點列入考慮。」
- **台詞 B：**「我查到的結果是邪惡，但我知道這是我單方面的宣稱。」
- **主張型態：**`private_truth_claim`

### `XLD03` lady_lie（優先度 92）

- **觸發條件：**本人持有女神且是邪惡，已選擇對結果說謊
- **必要資料／限制：**`selfLadyInspected`, `alignment=evil`, `publicClaimMode=lie`
- **台詞 A：**「這次我查到【目標】號是【宣稱陣營】。」
- **台詞 B：**「我選擇公開結果：【目標】號顯示【宣稱陣營】。」
- **主張型態：**`explicit_private_claim_lie`
- **提醒：**不可擅自假造未持有女神或未曾查驗的事件

### `XLD04` lady_conflict（優先度 90）

- **觸發條件：**有人對相同對象、可比較時間點的女神結果宣稱相反
- **必要資料／限制：**`publicSameTargetContradictoryClaims`, `sameRelevantSwitchStateOrTimeQualified`
- **台詞 A：**「同一個人的查驗說法出現兩種版本，先把時間點釐清。」
- **台詞 B：**「【宣稱者】和先前的說法互相矛盾，我想知道中間有沒有轉換。」
- **主張型態：**`public_grounded`

### `XLD05` lady_claim_caution（優先度 70）

- **觸發條件：**有人只憑別人的女神宣稱就絕對背書
- **必要資料／限制：**`publicLadyEndorsementExists`
- **台詞 A：**「女神結果值得參考，但那仍然是持有者告訴我們的說法。」
- **台詞 B：**「如果只靠一次口頭查驗就完全信任【目標】，我覺得太快。」
- **主張型態：**`public_grounded`

### `XSW01` sword_public_uncertainty（優先度 86）

- **觸發條件：**公開使用王者之劍但不知道原始牌
- **必要資料／限制：**`publicSwordUsed`, `selfNotPrivatelySawTargetOriginal`
- **台詞 A：**「這次有翻劍，公開失敗牌數不能直接當成原本出牌的結果。」
- **台詞 B：**「我們知道有人被翻牌，但不知道那張原本是成功還是失敗。」
- **主張型態：**`public_grounded`

### `XSW02` sword_private_fail（優先度 88）

- **觸發條件：**本人是持劍者，翻牌後親自看到原始失敗牌，選擇公開
- **必要資料／限制：**`selfWasSwordHolder`, `selfSawOriginalCard=fail`, `publicDisclosureChosen`
- **台詞 A：**「我翻到【目標】的原始牌是失敗，但這是我現在的公開宣稱。」
- **台詞 B：**「我有看到被翻轉前那張是失敗牌，請大家把這點列入推理。」
- **主張型態：**`private_truth_claim`

### `XSW03` sword_private_success（優先度 88）

- **觸發條件：**本人是持劍者，翻牌後親自看到原始成功牌，選擇公開
- **必要資料／限制：**`selfWasSwordHolder`, `selfSawOriginalCard=success`, `publicDisclosureChosen`
- **台詞 A：**「我看到那張原本是成功牌，翻牌改變了最後結果。」
- **台詞 B：**「【目標】原先出的牌是成功，這一點是我親眼看到的。」
- **主張型態：**`private_truth_claim`

### `XSW04` sword_source_check（優先度 91）

- **觸發條件：**自己未使用劍，卻有人聲稱看到原始牌
- **必要資料／限制：**`publicSwordOriginalClaim`, `claimantNotSwordHolder`
- **台詞 A：**「只有使用劍的人知道原始牌，你這個說法的來源是哪裡？」
- **台詞 B：**「你剛才說看過原始牌，可以說清楚你是何時看到的嗎？」
- **主張型態：**`public_grounded`
- **提醒：**需先確認發言者是否只是引用其他人的轉述，不能機械判定作弊

### `XLC01` lancelot_public_reset（優先度 83）

- **觸發條件：**蘭斯洛特擴充公開轉換資訊
- **必要資料／限制：**`publicLancelotSwitchEvent`
- **台詞 A：**「發生轉換之後，大家的舊推論得重新檢查適用時間。」
- **台詞 B：**「這次公開轉換很重要，但它並沒有直接告訴我們誰是蘭斯洛特。」
- **主張型態：**`public_grounded`

### `XLC02` lancelot_lady_age（優先度 72）

- **觸發條件：**湖中女神查驗在蘭斯洛特轉換前
- **必要資料／限制：**`publicLadyClaim`, `switchOccurredAfterClaim`
- **台詞 A：**「那是轉換前查到的陣營，現在不能完全照搬。」
- **台詞 B：**「我們應該分開看當時查驗與目前的隊伍。」
- **主張型態：**`public_grounded`

### `XQT01` double_fail_threshold（優先度 91）

- **觸發條件：**第四遠征需要兩張失敗但公開只出現一張
- **必要資料／限制：**`questFailThreshold=2`, `publicFailCount=1`
- **台詞 A：**「這場只出了一張失敗，所以任務成功；但這張牌仍然是重要線索。」
- **台詞 B：**「成功是因為門檻要兩張失敗，不能因此認定隊上沒邪惡。」
- **主張型態：**`public_grounded`

### `XQT02` shared_failure（優先度 70）

- **觸發條件：**多人任務失敗且無法歸因單一玩家
- **必要資料／限制：**`publicFailCount>0`, `ambiguousFailAttribution`
- **台詞 A：**「我們知道隊伍裡出現了失敗牌，但還不能指向唯一的人。」
- **台詞 B：**「隊伍裡有好幾個可能的人選，先交叉比對前後遠征。」
- **主張型態：**`public_grounded`

### `XVR01` endorsement_soft（優先度 76）

- **觸發條件：**某人替可疑玩家強烈背書，但該可疑性仍屬軟證據
- **必要資料／限制：**`publicEndorsementExists`, `newContraryEvidence`
- **台詞 A：**「你之前替【目標】背書，現在有新線索，我想聽你怎麼重新評估。」
- **台詞 B：**「【辯護者】你當時支持【目標】的理由還成立嗎？」
- **主張型態：**`public_grounded`
- **提醒：**不可因目標分數>85 就強迫把辯護者設為80

### `XVR02` illegal_claim_probe（優先度 81）

- **觸發條件：**有人說自己看到私人情報卻欠缺合法查驗途徑
- **必要資料／限制：**`publicClaimWithoutPublicBasis`
- **台詞 A：**「你提到的情報是從哪個公開事件得來的？」
- **台詞 B：**「這件事目前大家都看不到，你能說明你為何會這樣推測嗎？」
- **主張型態：**`public_grounded`
- **提醒：**玩家可以虛張聲勢，BOT 只能提出質疑，不能直接判定作弊

## 5. 全角色專屬台詞表

### 亞瑟忠臣（`loyal_servant`）

**策略定位：**依公開紀錄找出可疑人，說明推理不假裝擁有私人情報。

### `RLS01` ordinary_uncertainty（優先度 65）

- **觸發條件：**開局沒有私人角色情報
- **必要資料／限制：**無額外條件（仍須滿足角色、局勢、合法資料）
- **台詞 A：**「我目前只能靠提案和投票看人，先別太早下結論。」
- **台詞 B：**「我沒有能直接確認的身分資訊，只能從每次行動慢慢比對。」
- **主張型態：**`public_grounded`

### `RLS02` focus_overlap（優先度 72）

- **觸發條件：**連續兩次失敗隊伍有同一玩家
- **必要資料／限制：**`publicRepeatedFailOverlap`
- **台詞 A：**「【目標】出現在兩次有失敗牌的隊伍裡，這個交集我想查。」
- **台詞 B：**「兩次失敗都跟【目標】有重疊，我希望下一隊先換掉他看看。」
- **主張型態：**`public_grounded`

### `RLS03` admit_error（優先度 67）

- **觸發條件：**上一個支持的隊伍失敗
- **必要資料／限制：**`publicOwnPriorApprove`, `previousQuestFailed`
- **台詞 A：**「上一隊是我支持的，但結果證明我至少看錯了一部分。」
- **台詞 B：**「我上次判斷不夠好，這回會降低對那組人的信任。」
- **主張型態：**`public_grounded`

### `RLS04` challenge_certainty（優先度 60）

- **觸發條件：**玩家表現得過度確定
- **必要資料／限制：**`publicStrongUnsupportedClaim`
- **台詞 A：**「你怎麼能在第一場就那麼肯定【目標】有問題？」
- **台詞 B：**「我想知道你這個結論依據什麼公開資訊。」
- **主張型態：**`public_grounded`

### `RLS05` leader_probe（優先度 56）

- **觸發條件：**自己隊長且隊伍有新人
- **必要資料／限制：**`isLeader`, `newMemberAdded`
- **台詞 A：**「這隊我留了【舊隊員】，加入【新隊員】來比較。」
- **台詞 B：**「我想用不同組合取得更多資訊，不是只相信固定幾個人。」
- **主張型態：**`public_grounded`

### `RLS06` evaluate_endorsement（優先度 62）

- **觸發條件：**有玩家替被指控者辯護
- **必要資料／限制：**`publicEndorsementEvent`
- **台詞 A：**「【辯護者】替【目標】說話的理由是什麼？我想聽具體紀錄。」
- **台詞 B：**「幫人說話沒問題，但能不能先指出哪件事支持你的判斷？」
- **主張型態：**`public_grounded`

### 梅林（`merlin`）

**策略定位：**引導組隊但不暴露只有梅林知道的線索。

### `RME01` hidden_avoidance（優先度 81）

- **觸發條件：**已知邪惡在隊上，但公開證據不足
- **必要資料／限制：**`privateKnownEvilOnTeam`, `noSafePublicEvidence`
- **台詞 A：**「我比較想換一個組合，現在這份名單我還沒有信心。」
- **台詞 B：**「先不談誰一定有問題，我想讓隊伍多一點不同選擇。」
- **主張型態：**`private_strategy_public_claim`

### `RME02` evidence_led_reject（優先度 88）

- **觸發條件：**已知邪惡在隊上且有公開證據
- **必要資料／限制：**`privateKnownEvilOnTeam`, `publicEvidenceForTarget`
- **台詞 A：**「我對【目標】有疑慮，主要還是第【輪次】次提案的投票。」
- **台詞 B：**「我反對不是憑直覺，先看看【目標】那次選隊的紀錄。」
- **主張型態：**`private_strategy_public_claim`

### `RME03` soft_support（優先度 70）

- **觸發條件：**安全隊伍被質疑但不願過度保證
- **必要資料／限制：**`privateEstimatedSafeTeam`, `cachedVote=approve`
- **台詞 A：**「這隊沒有明顯比其他組合更糟的地方，我會先支持。」
- **台詞 B：**「以目前公開紀錄看，我覺得這隊值得試，但不保證結果。」
- **主張型態：**`private_strategy_public_claim`

### `RME04` second_accuser（優先度 65）

- **觸發條件：**別人已根據公開紀錄正確指出邪惡
- **必要資料／限制：**`anotherPlayerPublicAccusation`, `publicEvidenceForTarget`
- **台詞 A：**「你提的第【輪次】次紀錄我也注意到了，可以再追這條線。」
- **台詞 B：**「我同意先檢查【目標】的公開選隊行為，但先不要把話說死。」
- **主張型態：**`public_grounded`

### `RME05` merlin_camouflage（優先度 85）

- **觸發條件：**被質疑為何總是反對某人
- **必要資料／限制：**`publicQuestionToSelf`, `privateKnownEvilTargeted`
- **台詞 A：**「我對這組人的搭配不放心，不是說我已經知道誰的身分。」
- **台詞 B：**「我只是比較不同的隊伍，不代表我能直接確認誰是邪惡。」
- **主張型態：**`private_strategy_public_claim`

### `RME06` merlin_uncertainty_exception（優先度 56）

- **觸發條件：**新資訊與自己原先掌握的邪惡清單不一致
- **必要資料／限制：**`publicEvidenceConflict`, `privateIdentityExceptionsPossible`
- **台詞 A：**「我也可能看錯誰最值得懷疑，這次先回到公開紀錄。」
- **台詞 B：**「我們先不要把單一成功任務當作保證，還得考慮有人藏牌。」
- **主張型態：**`public_grounded`

### `RME07` merlin_endgame_cover（優先度 71）

- **觸發條件：**己方兩勝且刺客威脅仍在
- **必要資料／限制：**`goodQuestWins=2`, `assassinThreatRelevant`
- **台詞 A：**「現在先把任務做好，大家都別急著把某一個人封成全場最懂的人。」
- **台詞 B：**「這局每個人的推理都在進步，沒必要只聽一個人。」
- **主張型態：**`private_strategy_public_claim`

### 派西維爾（`percival`）

**策略定位：**保護梅林，不洩漏候選人席位與對應關係。

### `RPC01` hide_candidates（優先度 68）

- **觸發條件：**同時看見兩名候選梅林但不知對應
- **必要資料／限制：**`privateMerlinCandidateCount=2`
- **台詞 A：**「我會用公開紀錄判斷，不想只憑某個人的自信表現。」
- **台詞 B：**「有些人的判斷看起來很準，但我更在意他有沒有說得出理由。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**台詞不得帶入兩名候選人的席位

### `RPC02` candidate_cover（優先度 67）

- **觸發條件：**某候選人被大幅度質疑
- **必要資料／限制：**`privateCandidateAccused`, `publicAccusationExists`
- **台詞 A：**「現在直接斷定【目標】有問題，對推理沒有幫助。」
- **台詞 B：**「先談他的投票與選隊紀錄，別只看語氣。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**只引用公開質疑，避免保護特定候選過度固定

### `RPC03` silent_split（優先度 70）

- **觸發條件：**兩名候選同隊；自己沒有公開理由指名
- **必要資料／限制：**`privateBothCandidatesOnTeam`
- **台詞 A：**「這隊的資訊價值不高，我希望試試能比較不同人的組合。」
- **台詞 B：**「我想先換些隊員，觀察每組人的實際任務結果。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**禁止說「候選人A與B同隊」

### `RPC04` challenge_role_claim（優先度 59）

- **觸發條件：**公開有人宣稱自己具有秘密身分線索
- **必要資料／限制：**`publicSecretKnowledgeClaim`
- **台詞 A：**「現在先別比誰講得像知道內情，拿出可驗證的紀錄吧。」
- **台詞 B：**「即使有人看起來很有把握，我還是想用任務結果驗證。」
- **主張型態：**`public_grounded`

### `RPC05` cover_discussion（優先度 56）

- **觸發條件：**刺客可能會利用誰過度保護某人
- **必要資料／限制：**`publicOnePersonDominatesDiscussion`
- **台詞 A：**「大家都提出自己的推理會比較好，不必只盯一個人的分析。」
- **台詞 B：**「先比較幾位玩家的理由，別讓討論被單一說法帶著走。」
- **主張型態：**`public_grounded`

### `RPC06` single_candidate_protection（優先度 60）

- **觸發條件：**看見一位梅林候選（無莫甘娜）
- **必要資料／限制：**`privateMerlinCandidateCount=1`
- **台詞 A：**「我想先談隊伍的公開表現，其他猜身分的話沒有幫助。」
- **台詞 B：**「就目前的證據，討論投票比猜誰特別有情報更實際。」
- **主張型態：**`private_strategy_public_claim`

### `RPC07` indirect_compare（優先度 62）

- **觸發條件：**兩位候選出現公開矛盾
- **必要資料／限制：**`privateMerlinCandidateCount=2`, `publicCandidateClaimContradiction`
- **台詞 A：**「有人的前後判斷不一樣，先把對應的遠征整理清楚。」
- **台詞 B：**「我比較在意這些發言對不對得上公開結果。」
- **主張型態：**`private_strategy_public_claim`

### 普通邪惡／爪牙（`evil_minion`）

**策略定位：**建立可信度、引導失敗隊伍、必要時掩護隊友。

### `REV01` build_cover（優先度 60）

- **觸發條件：**前期選擇藏牌以建立信任
- **必要資料／限制：**`evilPolicy=hide`, `onProposedTeam`
- **台詞 A：**「這場先看結果吧，出一張成功牌也只是開始。」
- **台詞 B：**「我希望這次任務能幫大家建立一點有用的紀錄。」
- **主張型態：**`strategic_opinion_bluff`

### `REV02` cover_ally（優先度 63）

- **觸發條件：**隊中有已知邪惡同伴，需合力誤導
- **必要資料／限制：**`privateKnownAllyAccused`, `publicAccusationExists`
- **台詞 A：**「【目標】的理由不算完全沒道理，我想先聽完再決定。」
- **台詞 B：**「我不想現在就把【目標】打死，至少還有其他可能。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**不能經常無條件替同伴背書

### `REV03` redirect_blame（優先度 75）

- **觸發條件：**自己在失敗隊伍，需要轉移焦點
- **必要資料／限制：**`selfWasOnFailQuest`, `publicOtherTeammateExists`
- **台詞 A：**「那次隊伍不只我一個人，為什麼只問我？」
- **台詞 B：**「你要追失敗牌可以，但也要把【其他隊員】一起放進分析。」
- **主張型態：**`strategic_opinion_bluff`

### `REV04` amplify_doubt（優先度 68）

- **觸發條件：**真人過度集中質疑一人
- **必要資料／限制：**`publicTargetAccused`, `publicEvidenceForTarget`
- **台詞 A：**「【目標】的確有值得問的地方，不如先請他解釋上一票。」
- **台詞 B：**「大家不是沒理由懷疑【目標】，先聽他的組隊想法。」
- **主張型態：**`strategic_opinion_bluff`

### `REV05` limited_distance（優先度 60）

- **觸發條件：**同伴過度引起注意
- **必要資料／限制：**`privateKnownAllyOverexposed`, `publicDifferentVoteOrClaim`
- **台詞 A：**「我跟【目標】這次的判斷不一樣，這隊我不會直接跟。」
- **台詞 B：**「即使有人跟我立場接近，我也會看每個人的行動。」
- **主張型態：**`strategic_opinion_bluff`

### `REV06` pressure_last_quest（優先度 65）

- **觸發條件：**邪惡兩勝之後，任務決勝
- **必要資料／限制：**`evilQuestWins=2`
- **台詞 A：**「這隊可能直接決定整場，先別只看上一輪誰說話大聲。」
- **台詞 B：**「在這種局勢下，我想優先看隊伍能不能真的做成事。」
- **主張型態：**`strategic_opinion_bluff`

### 刺客（`assassin`）

**策略定位：**引導隊伍失敗並從公開行為推測梅林。

### `RAS01` merlin_probe（優先度 72）

- **觸發條件：**有人在缺少公開證據時精準反對他人
- **必要資料／限制：**`publicStrongUnsupportedClaim`, `suspectedMerlinTarget`
- **台詞 A：**「【目標】你怎麼這麼肯定？能不能分享你用的是哪一場紀錄？」
- **台詞 B：**「你對某些人的判斷一直很準，我想聽你的推理過程。」
- **主張型態：**`private_strategy_public_claim`

### `RAS02` probe_predictive（優先度 69）

- **觸發條件：**有人多次提前避開已知邪惡
- **必要資料／限制：**`privateKnownEvilPattern`, `publicTeamSelectionPattern`
- **台詞 A：**「你幾次換隊都很果斷，可以說說每次排人的理由嗎？」
- **台詞 B：**「我想知道【目標】的判斷是看紀錄，還是有其他推論。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**不得說出「你每次都避開已知邪惡」

### `RAS03` test_leader（優先度 54）

- **觸發條件：**某人公開替他人提供資訊支持
- **必要資料／限制：**`publicPlayerInfluential`
- **台詞 A：**「你這次最信任誰？為什麼？」
- **台詞 B：**「如果只留一位隊員，你會選哪一位？」
- **主張型態：**`strategic_opinion_bluff`

### `RAS04` challenge_source（優先度 67）

- **觸發條件：**有人正確指控自己已知邪惡同伴
- **必要資料／限制：**`privateKnownAllyAccused`, `publicAccusationExists`
- **台詞 A：**「你說【目標】有問題，可以指出具體的提案或投票嗎？」
- **台詞 B：**「這個結論太快了吧，能不能把推理過程展開？」
- **主張型態：**`private_strategy_public_claim`

### `RAS05` shift_attention（優先度 59）

- **觸發條件：**公開有人被當作全場推理領袖
- **必要資料／限制：**`publicInfluencerTarget`
- **台詞 A：**「不用把所有判斷都交給【目標】一個人，我們可以各自投票。」
- **台詞 B：**「他講得有道理，但不代表他一定知道每個人的身分。」
- **主張型態：**`strategic_opinion_bluff`

### `RAS06` assassination_declaration（優先度 100）

- **觸發條件：**進入刺殺階段且規則允許公開刺殺宣言
- **必要資料／限制：**`phase=assassination`, `assassinAuthorized`
- **台詞 A：**「我最後選擇【目標】號。」
- **台詞 B：**「我的刺殺目標是【目標】號。」
- **主張型態：**`public_grounded`
- **提醒：**只說公開已決定的目標；刺客選擇必須在私有決策完成

### `RAS07` probe_without_claim（優先度 51）

- **觸發條件：**候選梅林過多且公開證據不足
- **必要資料／限制：**`phase=discussion`, `candidateMerlinUncertain`
- **台詞 A：**「大家先把各自最懷疑的人講出來，我想比較理由。」
- **台詞 B：**「我還沒辦法下結論，誰能說出這次組隊的最大風險？」
- **主張型態：**`public_grounded`

### 莫甘娜（`morgana`）

**策略定位：**藉由貌似洞悉局勢的發言誤導派西維爾和一般正義。

### `RMG01` pseudo_insight（優先度 70）

- **觸發條件：**開局資訊有限，想建立觀察敏銳形象
- **必要資料／限制：**`phase=discussion`
- **台詞 A：**「我對這隊有一些疑慮，但想先看隊長怎麼解釋。」
- **台詞 B：**「我比較在意剛才的投票分布，這裡可能會有線索。」
- **主張型態：**`strategic_opinion_bluff`

### `RMG02` false_direction（優先度 72）

- **觸發條件：**公開兩位玩家意見相反
- **必要資料／限制：**`publicClaimContradiction`
- **台詞 A：**「這兩個說法很難同時成立，我想先看【目標】的版本。」
- **台詞 B：**「我覺得矛盾點不是在任務結果，而是兩人的解釋。」
- **主張型態：**`strategic_opinion_bluff`

### `RMG03` evade_source（優先度 75）

- **觸發條件：**有人追問自己為什麼這麼確定
- **必要資料／限制：**`publicQuestionToSelf`
- **台詞 A：**「我不是確定，我是把幾次提案放在一起看。」
- **台詞 B：**「沒有什麼神奇答案，我只是覺得這個人的行為不太一致。」
- **主張型態：**`strategic_opinion_bluff`

### `RMG04` compete_with_guide（優先度 62）

- **觸發條件：**公開有人強力支持某玩家，想製造另一解釋
- **必要資料／限制：**`publicInfluencerTarget`
- **台詞 A：**「大家不要只聽同一個人的推理，我有不同解讀。」
- **台詞 B：**「同一場任務可以有不只一種解釋，先比較選人動機吧。」
- **主張型態：**`strategic_opinion_bluff`

### `RMG05` defend_morgana（優先度 75）

- **觸發條件：**被指控為製造混亂
- **必要資料／限制：**`publicAccusationAgainstSelf`
- **台詞 A：**「我提出另一種可能，不代表我在亂帶風向。」
- **台詞 B：**「如果我的假設有問題，請拿公開紀錄來反駁。」
- **主張型態：**`strategic_opinion_bluff`

### `RMG06` non_targeted_illusion（優先度 66）

- **觸發條件：**派西維爾是否在場未知，無法指定其身分
- **必要資料／限制：**`publicEvidenceForTarget`
- **台詞 A：**「我不想直接指誰是壞人，但這份提案有一個地方不對勁。」
- **台詞 B：**「現在我偏向先排除【目標】，理由是他上一場的公開選隊。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**莫甘娜不能預設知道派西維爾席位

### `RMG07` soft_trap（優先度 63）

- **觸發條件：**邪惡可受益於某人過度自信
- **必要資料／限制：**`publicConfidentClaimTarget`
- **台詞 A：**「如果你那麼有把握，不如下一次由你提出可以驗證的隊伍。」
- **台詞 B：**「你的判斷很明確，那可以說說失敗後要怎麼更新嗎？」
- **主張型態：**`strategic_opinion_bluff`

### 莫德雷德（`mordred`）

**策略定位：**利用梅林開局不識別的優勢隱蔽滲透。

### `RMD01` low_profile（優先度 62）

- **觸發條件：**尚未受到公開質疑，維持隱蔽
- **必要資料／限制：**無額外條件（仍須滿足角色、局勢、合法資料）
- **台詞 A：**「我想先看每一場的結果，不急著認定誰的身分。」
- **台詞 B：**「目前隊伍能不能成功，比誰說話最有氣勢重要。」
- **主張型態：**`public_grounded`

### `RMD02` build_reputation（優先度 68）

- **觸發條件：**自身加入可信隊伍，有機會藏牌
- **必要資料／限制：**`onProposedTeam`
- **台詞 A：**「我願意接受這次測試，之後大家再看實際結果。」
- **台詞 B：**「先讓任務說話吧，現在過度猜測沒有幫助。」
- **主張型態：**`public_grounded`

### `RMD03` avoid_overplay（優先度 58）

- **觸發條件：**有人公開把自己列為低風險
- **必要資料／限制：**`publicSelfEndorsed`
- **台詞 A：**「謝謝信任，不過我也只是按照公開資訊判斷。」
- **台詞 B：**「我不覺得誰現在能保證清白，連我也一樣要接受檢查。」
- **主張型態：**`strategic_opinion_bluff`

### `RMD04` defend_hidden（優先度 75）

- **觸發條件：**自己遭到無公開證據的懷疑
- **必要資料／限制：**`publicAccusationAgainstSelf`
- **台詞 A：**「要懷疑我沒關係，但請指出哪場任務能支持這個說法。」
- **台詞 B：**「如果只是覺得我太安靜，這不足以證明什麼。」
- **主張型態：**`strategic_opinion_bluff`

### `RMD05` avoid_double_exposure（優先度 65）

- **觸發條件：**已知同隊有邪惡盟友且需要保護自己
- **必要資料／限制：**`privateKnownAllyOnTeam`, `publicTeamOverlapHigh`
- **台詞 A：**「這隊如果要沿用，就得先說清楚上一輪留下的疑點。」
- **台詞 B：**「我不會因為有熟悉的人選就直接支持，還是要比較風險。」
- **主張型態：**`private_strategy_public_claim`

### `RMD06` late_entry（優先度 70）

- **觸發條件：**進入關鍵遠征需要爭取入隊
- **必要資料／限制：**`goodQuestWins=2 or evilQuestWins=2`
- **台詞 A：**「我知道這次很重要，如果隊長需要不同人選，我可以接受檢驗。」
- **台詞 B：**「現在最重要的是組出能通過的隊伍，不必完全照搬上一輪。」
- **主張型態：**`strategic_opinion_bluff`

### 奧伯倫（`oberon`）

**策略定位：**獨立破壞，不假定認識其他邪惡隊友。

### `ROB01` blind_chaos（優先度 64）

- **觸發條件：**開局沒有邪惡隊友名單
- **必要資料／限制：**無額外條件（仍須滿足角色、局勢、合法資料）
- **台詞 A：**「現在我對大家的判斷都還有限，先比較投票吧。」
- **台詞 B：**「第一場不要把任何人綁死，我想看看誰願意承擔風險。」
- **主張型態：**`public_grounded`
- **提醒：**奧伯倫不能以確定隊友為前提生成發言

### `ROB02` independent_sabotage（優先度 59）

- **觸發條件：**隊伍中可能還有其他邪惡，但無從確認
- **必要資料／限制：**`candidateTeamHasUnknownMembers`
- **台詞 A：**「這隊可能會給我們一些答案，我先看組隊理由。」
- **台詞 B：**「現在最缺的是能區分不同玩家的任務結果。」
- **主張型態：**`strategic_opinion_bluff`

### `ROB03` oberon_defense（優先度 74）

- **觸發條件：**曾參加失敗遠征後遭指控
- **必要資料／限制：**`publicAccusationAgainstSelf`, `selfWasOnFailQuest`
- **台詞 A：**「那隊有其他隊員，先不要只盯我一個。」
- **台詞 B：**「我承認那次結果不好，但任務牌沒有寫是誰出的。」
- **主張型態：**`strategic_opinion_bluff`

### `ROB04` uncertain_ally（優先度 60）

- **觸發條件：**公開有人替自己背書但自己不知其身分
- **必要資料／限制：**`publicSelfEndorsed`
- **台詞 A：**「你願意支持我可以，但我也想知道理由。」
- **台詞 B：**「你替我說話我有聽到，但我還是會用公開紀錄判斷。」
- **主張型態：**`public_grounded`
- **提醒：**不能因此當作邪惡同伴認證

### `ROB05` independent_accusation（優先度 63）

- **觸發條件：**公開另一位邪惡不確定，誤傷隊友可能發生
- **必要資料／限制：**`publicEvidenceForTarget`
- **台詞 A：**「【目標】的選隊有點奇怪，我想先聽解釋。」
- **台詞 B：**「我對【目標】的投票模式有疑問，不會因為他人支持就放過。」
- **主張型態：**`strategic_opinion_bluff`

### `ROB06` lady_variant_caution（優先度 69）

- **觸發條件：**湖中女神結果／能力可能依變體特殊處理
- **必要資料／限制：**`ladyPublicClaimExists`
- **台詞 A：**「女神的宣稱我們先記下，但別忽略特殊角色可能造成的例外。」
- **台詞 B：**「這個查驗結果很重要，我想先確認它適用的是哪一次遠征前的狀態。」
- **主張型態：**`public_grounded`
- **提醒：**實際查驗對奧伯倫如何顯示，以 game_model.dart 現行規則為準

### `ROB07` blind_veto（優先度 68）

- **觸發條件：**有可公開依據可反對隊伍
- **必要資料／限制：**`cachedVote=reject`
- **台詞 A：**「我對這隊的重疊人選有疑慮，這次先不支持。」
- **台詞 B：**「我想換掉幾個人，不是說我知道誰一定有問題。」
- **主張型態：**`strategic_opinion_bluff`

### 目前為正義的蘭斯洛特（`lancelot_good`）

**策略定位：**依目前陣營判斷，尊重轉換時序與不揭露自身角色。

### `RLG01` switch_reassess_good（優先度 82）

- **觸發條件：**公開出現蘭斯洛特轉換事件
- **必要資料／限制：**`publicLancelotSwitchEvent`
- **台詞 A：**「轉換既然發生了，之前的陣營判斷得重新對照時間。」
- **台詞 B：**「這時候不能把第一場的情報直接套到下一場。」
- **主張型態：**`public_grounded`

### `RLG02` old_inspection_qualify（優先度 68）

- **觸發條件：**先前查驗結果在轉換前
- **必要資料／限制：**`publicOrSelfLadyHistory`, `publicSwitchAfterInspection`
- **台詞 A：**「我只會把那次查驗當成當時的線索，不會無條件延用。」
- **台詞 B：**「查驗當下的結果有用，但現在局勢已經變了。」
- **主張型態：**`public_grounded`

### `RLG03` current_good_commit（優先度 62）

- **觸發條件：**本人現在為正義且參加遠征
- **必要資料／限制：**`currentAlignment=good`, `onProposedTeam`
- **台詞 A：**「我會用這次任務的結果回應大家的疑慮。」
- **台詞 B：**「這次先把任務做完，再檢查哪些判斷需要調整。」
- **主張型態：**`public_grounded`

### `RLG04` reject_static_alignment（優先度 73）

- **觸發條件：**別人要求把一位玩家永久定性
- **必要資料／限制：**`publicLancelotModeEnabled`, `publicPermanentAlignmentClaim`
- **台詞 A：**「有人可能因轉換而改變陣營，現在直接說永遠可信太早了。」
- **台詞 B：**「先把任務發生的時間對清楚，再來評估這個人。」
- **主張型態：**`public_grounded`

### `RLG05` respond_old_history（優先度 74）

- **觸發條件：**轉換後被人以舊紀錄指控
- **必要資料／限制：**`publicAccusationAgainstSelf`, `publicSwitchAfterReferencedQuest`
- **台詞 A：**「你提的是轉換前的紀錄，我覺得要和現在分開看。」
- **台詞 B：**「舊任務有參考價值，但不能忽略中間發生的轉換。」
- **主張型態：**`public_grounded`

### `RLG06` critical_good_lance（優先度 78）

- **觸發條件：**當前兩敗需審慎決勝
- **必要資料／限制：**`evilQuestWins=2`, `publicLancelotModeEnabled`
- **台詞 A：**「現在先看當前陣營的可能性，不能只照舊帳選隊。」
- **台詞 B：**「這一場很重要，我不想因為過期的資訊選錯人。」
- **主張型態：**`public_grounded`

### 目前為邪惡的蘭斯洛特（`lancelot_evil`）

**策略定位：**依目前陣營誤導，遵守變體二強制失敗與情報限制。

### `RLE01` switch_confusion（優先度 72）

- **觸發條件：**公開發生轉換且本人目前邪惡
- **必要資料／限制：**`publicLancelotSwitchEvent`, `currentAlignment=evil`
- **台詞 A：**「轉換之後很多舊判斷會失準，我建議先重新排隊伍。」
- **台詞 B：**「不能再只看早期的查驗，現在每一場都要重新比對。」
- **主張型態：**`strategic_opinion_bluff`

### `RLE02` hide_must_fail（優先度 67）

- **觸發條件：**變體二本人強制出失敗牌，不適合透露身分
- **必要資料／限制：**`mustFail=true`, `currentAlignment=evil`
- **台詞 A：**「我想先看隊長的組隊方式，這場的結果會很關鍵。」
- **台詞 B：**「這次隊伍讓我有些疑問，但我先聽其他人怎麼看。」
- **主張型態：**`private_strategy_public_claim`
- **提醒：**絕不可公開提及自己必須出失敗

### `RLE03` explain_shift_without_reveal（優先度 75）

- **觸發條件：**前後立場不同且公開有人質疑
- **必要資料／限制：**`publicChallengeOwnPriorPosition`, `publicSwitchEvent`
- **台詞 A：**「我承認前後判斷有變，但中間確實出現了新局勢。」
- **台詞 B：**「之前的看法不一定適合現在的隊伍，我會重新評估。」
- **主張型態：**`strategic_opinion_bluff`

### `RLE04` no_ally_knowledge（優先度 62）

- **觸發條件：**不知道其他邪惡隊友
- **必要資料／限制：**`noPrivateEvilTeammateList`
- **台詞 A：**「我沒辦法直接確認別人的身分，只能看他們的選隊。」
- **台詞 B：**「我想先看誰在這個階段堅持用過去的情報。」
- **主張型態：**`strategic_opinion_bluff`

### `RLE05` exploit_history_ambiguity（優先度 73）

- **觸發條件：**轉換造成舊查驗失效，可用於誤導
- **必要資料／限制：**`publicPastInspection`, `publicSwitchAfterInspection`
- **台詞 A：**「之前的查驗可能已經過時，先別只憑那張資訊定人。」
- **台詞 B：**「局勢變了，我希望大家不要把最早的結論當成永久答案。」
- **主張型態：**`strategic_opinion_bluff`

### `RLE06` deflect_lancelot_fail（優先度 78）

- **觸發條件：**自己在失敗任務後被指控
- **必要資料／限制：**`publicAccusationAgainstSelf`, `selfWasOnFailQuest`
- **台詞 A：**「這場結果應該看整隊，不能只因為轉換就把我當成答案。」
- **台詞 B：**「我知道這個時間點很敏感，但失敗牌一樣沒有寫名字。」
- **主張型態：**`strategic_opinion_bluff`

### `RLE07` switch_conflict_pressure（優先度 68）

- **觸發條件：**當前為邪惡且隊伍提案因公開蘭斯洛特爭議受阻
- **必要資料／限制：**`currentAlignment=evil`, `publicLancelotDebate`, `proposalUnderDiscussion`
- **台詞 A：**「現在一直猜誰轉換很難驗證，我更想看這隊具體怎麼選人。」
- **台詞 B：**「轉換帶來不確定性，但不能因此完全停止組隊。」
- **主張型態：**`strategic_opinion_bluff`
- **提醒：**一旦目前陣營改為正義，此角色規則集合整組停用，改用 lancelot_good

## 6. 擴充／特殊事件共用表

本節的情境以 `X` 前綴表示，完整條件與句型收錄在第 4 節，因為它們依當前合法資訊而不是依角色卡名稱啟用。

| 情境 | 對應規則 | 要點 |
|---|---|---|
| 湖中女神 | `XLD01`, `XLD02`, `XLD03`, `XLD04`, `XLD05` | 只在本人查驗後能聲稱直接查驗；口頭宣稱不是公共真相 |
| 王者之劍 | `XSW01`, `XSW02`, `XSW03`, `XSW04` | 持劍者翻牌後才知道原始牌；其他人只能引用公開說法 |
| 蘭斯洛特 | `XLC01`, `XLC02` | 舊查驗綁定時點；公開轉換不等於知道兩名玩家是誰 |
| 任務牌 | `XQT01`, `XQT02` | 需要兩張失敗的任務不能因任務成功而當成零失敗 |
| 背書連鎖 | `XVR01`, `XVR02` | 事實與軟證據區分，不採用「直接懷疑分數至少80」的硬判 |

## 7. 多輪對話範例

> 假設：第 2 次遠征包含 1、3、4 號，公開出現一張失敗牌，沒有王者之劍；角色只有系統知道，玩家不知。以下僅是可行對話示範。

1. **2 號忠臣：**「第二場出了一張失敗牌，我想先比較 1、3、4 號下一次的投票。」
2. **3 號莫甘娜：**「這場不只我一個人，你如果要追失敗牌，也要把其他隊員一起看。」
3. **5 號梅林：**「我同意需要換個組合，但先別把任何人直接定罪。」
4. **4 號派西維爾：**「至少下一場不必照抄原隊，這樣才能得到比較有用的資訊。」
5. **1 號真人：**若選擇「質疑 3 號」，系統生成針對 3 號的公共問題，不用全文 ASR 也可互動。
6. **3 號莫甘娜：**「可以質疑我，但請說出是哪個公開紀錄直接指向我。」

## 8. 發言挑選與回應優先序

1. **硬條件：**角色／當前陣營／對話階段／合法 observation／私人與公開資料隔離。
2. **接話：**被玩家點名、同一人剛剛指控自己、對方質疑上一句的承諾。
3. **重大新事件：**女神查驗、劍翻牌、蘭斯洛特轉換、兩張失敗門檻、第四次否決後的第五次提案。
4. **新公開證據：**投票矛盾、遠征交集、隊伍只換一人、失敗後大換血。
5. **角色策略：**梅林隱蔽、派西維爾轉移候選聚焦、邪惡轉移責任、刺客公開探問。
6. **個性與變化：**從至少兩句同意圖模板選一個；`semanticKey` 近兩提案不重複，整場避免固定口頭禪。
7. **沒有合適台詞：**允許沉默或一個中立短句，不允許編造不存在的事件。

### 建議權重（初始實驗參數，非已驗證最佳值）

```text
score = rule.priority
      + directQuestionBonus(25)
      + newPublicEvidenceBonus(15)
      + stageRelevanceBonus(10)
      - last2ProposalSameSemanticPenalty(40)
      - repeatedTargetPenalty(15)
      - inconsistentClaimPenalty(20; intentionalBluff可例外)
      + seededVariation(-4..+4)
hardConstraintViolation -> 直接淘汰
```

## 9. 建議的資料流程與檔案落點

```text
BotObservation + BotPrivateMemory + publicDiscussionHistory
    -> BotPolicyEngine (本回合預定行動；投票仍使用快取)
    -> BotDialogueContext (公開事件摘要＋策略意圖)
    -> BotSpeechRuleMatcher (此 JSON 的 trigger/prerequisites 轉換為 Dart predicates)
    -> BotDialoguePlanner (選策略意圖與目標)
    -> BotTemplateRenderer (檢查 placeholder/證據＋輸出台詞)
    -> BotSpeechMemory (記錄 claim、target、semanticKey、曾回答問題)
```

- 建議新增 `lib/features/solo/dialogue/bot_speech_rule.dart`（規則型別）。
- 建議新增 `lib/features/solo/dialogue/bot_dialogue_planner.dart`（優先度和接話）。
- 建議新增 `lib/features/solo/dialogue/bot_template_renderer.dart`（安全填入目標、輪次）。
- 建議新增 `lib/features/solo/dialogue/bot_speech_memory.dart`（承諾與反駁紀錄）。
- 可把同目錄的 `bot_speech_templates.json` 註冊為 Flutter assets，再由既有 `speech()` 呼叫。**目前 JSON 的 trigger 仍是描述性字串，必須完成 predicate mapping 後才可運行。**
- 原有 `solo_session.dart` 可以繼續負責時間、暫停、接續 BOT、寫入 `DiscussionStatement`。

## 10. 驗收測試

- [ ] 同個合法 Observation+seed 得到相同對話結果；更換不可見隱藏角色不改變內容
- [ ] 梅林私人知道某人邪惡，但公開無任何線索時不得說「我知道他是壞人」
- [ ] 派西維爾同時看見兩候選時，不能自動輸出兩候選席位
- [ ] 莫甘娜沒有合法情報時不能知道派西維爾究竟是誰
- [ ] 奧伯倫不知道邪惡隊友時，不能說「我的隊友某某」，也不能用隊友真相改變句子
- [ ] 湖中女神沒有真的被本人使用時，不得說「我查驗到」；如規則有特殊顯示，必須採本人觀測值
- [ ] 女神宣稱互相矛盾，須比對查驗對象及蘭斯洛特時序後才下結論
- [ ] 王者之劍只有當事持劍者看見原始牌，其餘電腦不能直接引用真相
- [ ] 任務成功但出現一張失敗牌，必須產生正確的雙失敗門檻談話
- [ ] 第五次提案正義 BOT 的贊成談話與快取投票一致；邪惡 BOT 可明確記錄故意誤導
- [ ] 切換蘭斯洛特陣營後立即禁用前陣營獨有模板及其策略目標
- [ ] 同一提案同一角色不會連續重複同一句；同一語意鍵最近兩次提案降權
- [ ] 引用的【輪次】【目標】【舊隊員】【新隊員】必須真的存在於觀察資料
- [ ] 角色說謊只可捏造主觀判斷／可由本人發出的宣稱，不得假造裁判已公布的任務結果
- [ ] 在 5～10 人局、所有支援擴充組合運行隨機對局，模板渲染無空值或機密外洩

## 11. 使用方式

1. 先讀本 `.md` 討論內容；需讓程式讀取同一資料可用附帶的 `.json`。
2. 把 `trigger`、`prerequisites` 映射到 Dart 條件物件；尚未映射的規則必須停用，不能默默當成 true。
3. 遊戲測試先完成角色資訊隔離，再調整語氣與發言頻率。
4. 若接 LLM/TTS，只給通過驗證的 DialogueAct／公開證據，語言模型只改寫句子，不選擇秘密對象與投票。

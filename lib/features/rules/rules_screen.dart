import 'package:flutter/material.dart';
import '../../core/assets.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_model.dart';
import '../lobby/room_model.dart';
import '../table/components.dart';
import '../table/expansion_pieces.dart';

enum RulesTopic {
  goal('遊戲目標', Icons.flag_outlined),
  round('一輪怎麼玩', Icons.loop),
  players('人數與任務', Icons.groups_outlined),
  roles('角色介紹', Icons.badge_outlined),
  lady('湖中女神', Icons.water_drop_outlined),
  lancelot('蘭斯洛特', Icons.swap_horiz),
  excalibur('王者之劍', Icons.colorize_outlined),
  tips('新手技巧', Icons.lightbulb_outline),
  app('App 操作', Icons.touch_app_outlined);

  const RulesTopic(this.title, this.icon);
  final String title;
  final IconData icon;
}

/// How to play, for players who have never played Avalon.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key, this.initial = RulesTopic.goal});
  final RulesTopic initial;

  static Future<void> open(BuildContext context,
          [RulesTopic topic = RulesTopic.goal]) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => RulesScreen(initial: topic)));

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  late RulesTopic topic = widget.initial;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _show(RulesTopic t) {
    setState(() => topic = t);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: FantasyBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 168,
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(children: [
                          IconButton(
                              tooltip: '返回',
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.arrow_back),
                              color: AvalonTheme.gold,
                              constraints: const BoxConstraints.tightFor(
                                  width: 36, height: 36),
                              padding: EdgeInsets.zero),
                          const SizedBox(width: 4),
                          const Text('遊戲規則',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AvalonTheme.gold)),
                        ]),
                        const SizedBox(height: 6),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(children: [
                              for (final t in RulesTopic.values)
                                _TopicTile(
                                    topic: t,
                                    selected: t == topic,
                                    onTap: () => _show(t)),
                            ]),
                          ),
                        ),
                      ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GoldPanel(
                    padding: EdgeInsets.zero,
                    child: Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        key: ValueKey(topic),
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(topic.title,
                                style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AvalonTheme.gold)),
                            const SizedBox(height: 10),
                            ..._content(topic),
                            const SizedBox(height: 16),
                            if (topic.index < RulesTopic.values.length - 1)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  key: const ValueKey('rulesNext'),
                                  onPressed: () => _show(
                                      RulesTopic.values[topic.index + 1]),
                                  icon: const Icon(Icons.arrow_forward),
                                  label: Text(
                                      '下一篇：${RulesTopic.values[topic.index + 1].title}'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );

  List<Widget> _content(RulesTopic t) => switch (t) {
        RulesTopic.goal => [
            const _P('玩家分成「正義」與「邪惡」兩個陣營，每個人的身分都是秘密。'
                '大家一起出任務，邪惡玩家混在隊伍裡暗中破壞。'),
            const _SideCard(
                good: true,
                title: '正義陣營（亞瑟的忠臣）',
                lines: ['讓 3 次任務成功。', '最後還要保護梅林，不能被刺客認出來。']),
            const _SideCard(good: false, title: '邪惡陣營（莫德雷德的爪牙）', lines: [
              '讓 3 次任務失敗；或',
              '讓組隊連續 5 次被否決；或',
              '正義完成 3 次任務後，由刺客成功指認出梅林（逆轉勝）。',
            ]),
            const _P('邪惡玩家彼此認識（奧伯倫例外），正義玩家則不知道誰是誰，'
                '只有梅林知道壞人是誰。所以正義要靠討論、投票和任務結果推理。'),
          ],
        RulesTopic.round => const [
            _Step(1, '組隊', '隊長（有皇冠的人）挑出這次任務需要的人數，可以選自己。'),
            _Step(2, '討論', '大家輪流發言，說服別人或指出可疑的人。可以說謊，但不能把卡片給別人看。'),
            _Step(3, '投票', '所有人同時蓋牌投「贊成」或「反對」，一起翻開。'
                '超過半數贊成才通過，平手算否決。'),
            _Step(4, '否決', '隊長換成下一位玩家，重新組隊。同一個任務連續 5 次否決，邪惡直接獲勝。'),
            _Step(5, '出任務', '通過的隊員秘密打出任務牌。正義只能出「成功」；邪惡可以選「成功」或「失敗」。'),
            _Step(6, '公開結果', '任務牌洗勻後翻開，看不出是誰出的。只要有 1 張失敗，任務就失敗'
                '（7 人以上的第 4 次任務要 2 張失敗才算失敗）。'),
            _Step(7, '下一輪', '隊長傳給下一位，繼續下一個任務。先拿到 3 次成功或 3 次失敗的一方贏。'),
            _Step(8, '刺殺梅林', '正義拿到 3 次成功時，邪惡可以一起討論，最後由刺客指定一個人。'
                '指中梅林，邪惡逆轉獲勝；指錯，正義獲勝。'),
          ],
        RulesTopic.players => [
            const _P('人數決定陣營比例，以及每次任務要派幾個人。'),
            const _PlayersTable(),
            const _P('＊ 7 人以上時，第 4 次任務要出現 2 張失敗才算失敗。'),
            const _P('角色以外的名額會自動補上「亞瑟的忠臣」與「莫德雷德的爪牙」。'
                '梅林與刺客每局固定加入。'),
          ],
        RulesTopic.roles => [
            const _P('除了梅林與刺客，其他特殊角色可以在開局前自由加入。'),
            for (final (role, text) in _roles)
              _RoleRow(role: role, text: text),
            const _P('建議：第一次玩只用梅林＋刺客。熟悉後加入派西維爾＋莫甘娜，遊戲會更好玩。'),
          ],
        RulesTopic.lady => [
            _Picture(
                picture: GameCard(Assets.ladyOfTheLake, width: 70),
                text: '湖中女神是開局前可勾選的擴充，建議 7 人以上使用。'),
            const _Bullets([
              '開局時交給第一位隊長右手邊的玩家，桌上會在他的座位旁放一張湖中女神卡。',
              '第 2、3、4 次任務結束後，持有者選一名玩家，查看他的陣營（只看正義或邪惡，不看角色）。',
              '查到的結果只有持有者看得到。他可以說出來，也可以說謊，但不能給別人看。',
              '查完後，湖中女神交給被查驗的人，下一次換他使用。',
              '拿過湖中女神的人不能被查驗。',
            ]),
            Wrap(spacing: 10, children: [
              GameCard(Assets.loyaltyGood, width: 54),
              GameCard(Assets.loyaltyEvil, width: 54),
            ]),
          ],
        RulesTopic.lancelot => [
            Wrap(spacing: 10, runSpacing: 8, children: [
              GameCard(Assets.role(Role.lancelotGood, 0), width: 60),
              GameCard(Assets.role(Role.lancelotEvil, 0), width: 60),
              const SizedBox(width: 6),
              WideCard(Assets.loyaltySwitch, width: 96),
              WideCard(Assets.loyaltyNoSwitch, width: 96),
            ]),
            const SizedBox(height: 10),
            const _Bullets([
              '加入正義蘭斯洛特和邪惡蘭斯洛特，各占一個正義、一個邪惡名額。需要 7 人以上才能使用。',
              '兩位蘭斯洛特互相不認識。邪惡蘭斯洛特會被其他壞人看到，但他看不到其他壞人。',
              '遊戲中可能翻出「轉換陣營」卡，兩位蘭斯洛特就會暗中交換陣營。'
                  '出任務的限制和最後的輸贏，都看他當下屬於哪一邊。',
              '牌桌上的記分板右上角會顯示 5 張轉換陣營卡。',
            ]),
            const _H('變體一：每輪翻牌'),
            const _Bullets([
              '7 張轉換牌（5 張不變、2 張轉換）洗勻。',
              '從第 3 次任務開始，每次任務開始前翻 1 張（最多翻 3 張）。組隊被否決不會再翻。',
              '翻到「轉換」時兩人換邊；可能換 0 次、1 次或 2 次。',
            ]),
            const _H('變體二：開局公開'),
            const _Bullets([
              '7 張抽 5 張，開局就正面放在 5 個任務上，大家都知道哪一輪會換邊。',
              '正義方的蘭斯洛特只能出成功；邪惡方的蘭斯洛特必須出失敗。',
            ]),
          ],
        RulesTopic.excalibur => [
            _Picture(
                picture: Token(Assets.excalibur, size: 90),
                text: '王者之劍是開局前可勾選的擴充。'),
            const _Bullets([
              '隊長提案時，要把王者之劍交給一名隊員（不能給自己）。',
              '所有隊員打出任務牌後、公開之前，持劍者可以指定另一名隊員，把他的牌翻轉：成功變失敗、失敗變成功。',
              '持劍者會看到那張牌原本是什麼，這是很強的情報。也可以選擇不使用。',
              '公開結果時，所有人都會知道「誰翻了誰的牌」，但不知道原本是什麼。',
            ]),
          ],
        RulesTopic.tips => const [
            _H('正義'),
            _Bullets([
              '記住每次組隊和每個人的投票。贊成了失敗隊伍的人值得懷疑。',
              '任務失敗時，隊伍裡至少有一個壞人。',
              '梅林說話要含蓄：太準會被刺客找出來。',
              '派西維爾可以替梅林擋刀，假裝自己是梅林。',
            ]),
            _H('邪惡'),
            _Bullets([
              '不一定每次都要出失敗。偶爾出成功，可以騙到信任。',
              '同一隊有兩個壞人時要小心，兩張失敗會讓兩人都被懷疑。',
              '留意誰好像「知道得太多」，那可能是梅林，最後告訴刺客。',
            ]),
            _H('大家'),
            _Bullets([
              '可以說謊、可以演戲，但絕對不能把自己的卡給別人看。',
              '多機遊玩時，右上角的筆記本可以記下每個人的投票與想法。',
            ]),
          ],
        RulesTopic.app => const [
            _H('一機遊玩'),
            _Bullets([
              '一支手機輪流傳。畫面出現「請將手機交給…」時，交給那位玩家，其他人移開視線。',
              '本人按「我是本人，開啟秘密畫面」後才會顯示身分、投票或出牌。',
              '看完按「記住了，隱藏並交給下一位」，卡片會蓋回去再交出去。',
            ]),
            _H('多機遊玩'),
            _Bullets([
              '每人用自己的手機。房主建立房間，把 6 位數房號告訴大家。',
              '房主在大廳設定角色、發言方式與擴充規則，人到齊後開始。',
              '語音：按麥克風開麥，離開 App 時會自動關麥。',
              '中途離開可選「暫時離開」（之後用房號回到座位）或「離開房間」（對局會中止）。',
            ]),
            _H('牌桌'),
            _Bullets([
              '隊長在座位上點選隊員，再按下方按鈕提案。',
              '標題列的「？」可以隨時打開這份規則。',
            ]),
          ],
      };

  static const _roles = [
    (Role.merlin, '正義。知道所有邪惡玩家（莫德雷德除外）。要暗中引導大家，但別被刺客認出來。'),
    (Role.percival, '正義。知道誰是梅林；如果有莫甘娜，會看到兩個人，分不出哪個才是真的。'),
    (Role.loyal, '正義。沒有特殊情報，靠觀察與推理。'),
    (Role.assassin, '邪惡。正義完成 3 次任務後，由他指認梅林。'),
    (Role.morgana, '邪惡。在派西維爾眼中看起來像梅林，用來混淆他。'),
    (Role.mordred, '邪惡。梅林看不到他。'),
    (Role.oberon, '邪惡。不認識其他壞人，其他壞人也不認識他；但梅林看得到他。'),
    (Role.minion, '邪惡。一般壞人，知道其他同伴是誰。'),
  ];
}

class _TopicTile extends StatelessWidget {
  const _TopicTile(
      {required this.topic, required this.selected, required this.onTap});
  final RulesTopic topic;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected
              ? AvalonTheme.violet.withValues(alpha: .35)
              : AvalonTheme.raised.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            key: ValueKey('rules_${topic.name}'),
            borderRadius: BorderRadius.circular(9),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(children: [
                Icon(topic.icon,
                    size: 17,
                    color: selected ? AvalonTheme.gold : AvalonTheme.muted),
                const SizedBox(width: 8),
                Text(topic.title,
                    style: TextStyle(
                        fontSize: 13.5,
                        color: selected ? AvalonTheme.gold : Colors.white)),
              ]),
            ),
          ),
        ),
      );
}

const _body = TextStyle(fontSize: 14, height: 1.6, color: Color(0xFFE8E2D2));

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(text, style: _body));
}

class _H extends StatelessWidget {
  const _H(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 6),
        child: Text(text,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AvalonTheme.gold)),
      );
}

class _Bullets extends StatelessWidget {
  const _Bullets(this.lines);
  final List<String> lines;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                  padding: EdgeInsets.only(top: 9, right: 8),
                  child: Icon(Icons.circle, size: 5, color: AvalonTheme.gold),
                ),
                Expanded(child: Text(line, style: _body)),
              ]),
            ),
        ]),
      );
}

class _Step extends StatelessWidget {
  const _Step(this.number, this.title, this.text);
  final int number;
  final String title, text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                  colors: [Color(0xFFF0D59A), Color(0xFFA67C3A)]),
            ),
            child: Text('$number',
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF2A1708))),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: '$title　',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: AvalonTheme.gold)),
                TextSpan(text: text),
              ]),
              style: _body,
            ),
          ),
        ]),
      );
}

class _SideCard extends StatelessWidget {
  const _SideCard(
      {required this.good, required this.title, required this.lines});
  final bool good;
  final String title;
  final List<String> lines;
  @override
  Widget build(BuildContext context) {
    final color = good ? const Color(0xFF6FC3FF) : const Color(0xFFFF6B5E);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Image.asset(good ? Assets.logoGood : Assets.logoEvil,
            width: 40, height: 40, cacheWidth: 120),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            for (final line in lines) Text(line, style: _body),
          ]),
        ),
      ]),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.role, required this.text});
  final Role role;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          GameCard(Assets.role(role, 0), width: 48, elevation: 3),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(role.label,
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: role.isEvil
                              ? const Color(0xFFFF8A7E)
                              : const Color(0xFF8FD0FF))),
                  Text(text, style: _body),
                ]),
          ),
        ]),
      );
}

class _Picture extends StatelessWidget {
  const _Picture({required this.picture, required this.text});
  final Widget picture;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          picture,
          const SizedBox(width: 14),
          Expanded(child: Text(text, style: _body)),
        ]),
      );
}

class _PlayersTable extends StatelessWidget {
  const _PlayersTable();
  @override
  Widget build(BuildContext context) {
    Widget cell(String text, {bool head = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: head ? FontWeight.bold : FontWeight.normal,
                  color: color ?? (head ? AvalonTheme.gold : Colors.white))),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Table(
        key: const ValueKey('playersTable'),
        border: TableBorder.symmetric(
            inside: BorderSide(color: AvalonTheme.gold.withValues(alpha: .18))),
        children: [
          TableRow(children: [
            cell('人數', head: true),
            cell('正義', head: true),
            cell('邪惡', head: true),
            for (var q = 1; q <= 5; q++) cell('任務$q', head: true),
          ]),
          for (var n = 5; n <= 10; n++)
            TableRow(children: [
              cell('$n 人', head: true),
              cell('${n - Room.evilCount(n)}', color: const Color(0xFF8FD0FF)),
              cell('${Room.evilCount(n)}', color: const Color(0xFFFF8A7E)),
              for (var q = 0; q < 5; q++)
                cell('${questTeamSize(n, q)}${q == 3 && n >= 7 ? '＊' : ''}'),
            ]),
        ],
      ),
    );
  }
}

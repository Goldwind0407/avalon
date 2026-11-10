import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/assets.dart';
import '../../core/theme.dart';
import '../lobby/room_model.dart';
import '../table/card_reveal.dart';
import '../table/components.dart';
import '../table/effects.dart';
import '../table/quest_board.dart';
import '../table/table_surface.dart';
import 'game_model.dart';

Duration _ms(int v) => Duration(milliseconds: v);

/// Landscape table-top game screen (pass & play on one device).
///
/// The rules live in [AvalonGame]; this class only stages them: pieces are
/// dealt, handed out, played face down and turned over like on a real table.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.room});
  final Room room;
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with WidgetsBindingObserver {
  static const _good = Color(0xFF6FC3FF);
  static const _evil = Color(0xFFFF6B5E);
  static const _ink = Color(0xFFEDE3CC);
  static const _numerals = ['一', '二', '三', '四', '五'];

  late AvalonGame game;
  late List<int> variants;
  bool revealed = false;
  final selected = <int>{};
  bool? choice;
  List<bool> questOrder = const [];
  final _rng = Random();

  // ── staging ──
  final _flights = GlobalKey<FlightLayerState>();
  final _shaker = GlobalKey<ShakerState>();
  final _deckKey = GlobalKey(), _pileKey = GlobalKey();
  var _choiceKeys = {true: GlobalKey(), false: GlobalKey()};
  late final List<GlobalKey> _plateKeys, _crownKeys, _shieldKeys, _voteKeys;
  late final List<int> _bumps;
  final _timers = <Timer>[];
  double _s = 1;

  /// Role cards are being dealt; the first hand-off waits for it.
  bool _dealing = false;

  /// A short moment with the table in clear view, so everyone sees the
  /// piece that was just played land before the phone is passed on.
  bool _interlude = false;

  /// The chosen card is being turned face down before it is played.
  bool _committing = false;

  /// The identity card is being turned face down before passing on.
  bool _hiding = false;
  bool _crownFlying = false;
  final _voteLanding = <int>{}, _shieldLanding = <int>{};
  int _pileLanding = 0;
  int _announceId = 0;
  (String, String, int)? _announcement;
  int? _assassinTarget;
  bool _assassinShown = false;

  @override
  void initState() {
    super.initState();
    final n = widget.room.players.length;
    List<GlobalKey> keys() => List.generate(n, (_) => GlobalKey());
    _plateKeys = keys();
    _crownKeys = keys();
    _shieldKeys = keys();
    _voteKeys = keys();
    _bumps = List.filled(n, 0);
    _newGame();
    WidgetsBinding.instance.addObserver(this);
  }

  void _newGame() {
    game = AvalonGame(widget.room);
    // pick a different artwork for every loyal servant / minion
    final seen = <Role, int>{};
    variants = [
      for (final r in game.roles)
        seen.update(r, (v) => v + 1, ifAbsent: () => 0)
    ];
    _interlude = _crownFlying = _assassinShown = false;
    _voteLanding.clear();
    _shieldLanding.clear();
    _pileLanding = 0;
    _announcement = null;
    _assassinTarget = null;
    _deal();
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && mounted) {
      setState(() => revealed = false);
    }
  }

  void _after(Duration delay, VoidCallback fn) {
    late final Timer timer;
    timer = Timer(delay, () {
      _timers.remove(timer);
      if (mounted) fn();
    });
    _timers.add(timer);
  }

  /// Deals one face-down role card from the deck to every seat.
  void _deal() {
    _dealing = true;
    final n = widget.room.players.length;
    // wait until the seats have slid into place
    _after(_ms(900), () {
      final deck = rectOf(_deckKey);
      for (var i = 0; i < n; i++) {
        final plate = rectOf(_plateKeys[i]);
        if (deck == null || plate == null) continue;
        _flights.currentState?.launch(Flight(
          from: deck,
          to: Rect.fromCenter(
              center: plate.center,
              width: deck.width * .5,
              height: deck.height * .5),
          delay: _ms(120 * i),
          duration: _ms(480),
          arc: -28 * _s,
          turns: i.isEven ? .5 : -.5,
          builder: (w) => CardBack(width: w, elevation: 6),
          onDone: () {
            if (!mounted) return;
            HapticFeedback.selectionClick();
            setState(() => _bumps[i]++);
          },
        ));
      }
      _after(_ms(120 * (n - 1) + 480 + 280),
          () => setState(() => _dealing = false));
    });
  }

  void act(VoidCallback action, {bool interlude = false}) {
    HapticFeedback.mediumImpact();
    final before = game;
    final oldPhase = game.phase, oldLeader = game.leader;
    setState(() {
      action();
      revealed = false;
      selected.clear();
      choice = null;
      _committing = _hiding = false;
      _shieldLanding.clear();
      if (interlude) _interlude = true;
      if (!identical(before, game)) return;
      if (game.phase == GamePhase.questResult &&
          oldPhase != GamePhase.questResult) {
        final q = game.history.last;
        questOrder = [
          ...List.filled(q.team.length - q.fails, true),
          ...List.filled(q.fails, false)
        ]..shuffle(_rng);
      }
      if (game.phase == GamePhase.team && oldPhase != GamePhase.team) {
        if (game.leader != oldLeader) _passCrown(oldLeader, game.leader);
        if (oldPhase != GamePhase.voteResult) {
          _announceId++;
          _announcement = (
            '第${_numerals[game.questNumber - 1]}次遠征',
            '隊長 ${player(game.leader)}　·　派出 ${game.requiredTeam} 人'
                '${game.failsRequired == 2 ? '　·　需兩張失敗' : ''}',
            oldPhase == GamePhase.questResult ? 1500 : 350,
          );
        }
      }
    });
    if (interlude) {
      _after(_ms(1000), () => setState(() => _interlude = false));
    }
  }

  /// The crown is carried from the old leader to the new one.
  void _passCrown(int from, int to) {
    _crownFlying = true;
    void land() {
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _crownFlying = false;
        _bumps[to]++;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final a = rectOf(_crownKeys[from]), b = rectOf(_crownKeys[to]);
      final layer = _flights.currentState;
      if (!mounted || a == null || b == null || layer == null) return land();
      layer.launch(Flight(
        from: a,
        to: b,
        delay: _ms(350),
        duration: _ms(850),
        arc: -46 * _s,
        builder: (w) => Token(Assets.leaderToken, size: w, elevation: 7),
        onDone: land,
      ));
    });
  }

  /// The leader hands a shield to (or takes it back from) a seat.
  void _toggleSeat(int i) {
    HapticFeedback.selectionClick();
    if (selected.contains(i)) {
      setState(() {
        selected.remove(i);
        _shieldLanding.remove(i);
      });
      return;
    }
    setState(() {
      selected.add(i);
      _shieldLanding.add(i);
    });
    void land() {
      if (!mounted || !_shieldLanding.contains(i)) return;
      HapticFeedback.lightImpact();
      setState(() {
        _shieldLanding.remove(i);
        _bumps[i]++;
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final from = rectOf(_plateKeys[game.leader]);
      final to = rectOf(_shieldKeys[i]);
      final layer = _flights.currentState;
      if (!mounted || from == null || to == null || layer == null) {
        return land();
      }
      layer.launch(Flight(
        from: Rect.fromCenter(
            center: from.center, width: to.width, height: to.height),
        to: to,
        duration: _ms(420),
        arc: -22 * _s,
        builder: (w) => Token(Assets.teamToken, size: w, elevation: 6),
        onDone: land,
      ));
    });
  }

  /// Turns the chosen card face down, then plays it onto the table.
  void _commit(VoidCallback action,
      {required CardDeck deck,
      required GlobalKey target,
      required VoidCallback onLaunch,
      required VoidCallback onLand}) {
    if (_committing || choice == null) return;
    HapticFeedback.selectionClick();
    final cardKey = _choiceKeys[choice!]!;
    setState(() => _committing = true);
    _after(_ms(430), () {
      final from = rectOf(cardKey);
      onLaunch();
      act(action, interlude: true);
      void land() {
        if (!mounted) return;
        HapticFeedback.lightImpact();
        setState(onLand);
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final to = rectOf(target);
        final layer = _flights.currentState;
        if (!mounted || from == null || to == null || layer == null) {
          return land();
        }
        layer.launch(Flight(
          from: from,
          to: to,
          duration: _ms(640),
          arc: -34 * _s,
          turns: .5,
          builder: (w) => CardBack(width: w, deck: deck, elevation: 10),
          onDone: land,
        ));
      });
    });
  }

  Future<void> leave() async {
    if (game.phase != GamePhase.finished) {
      setState(() => revealed = false);
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('結束這場對局？'),
                content: const Text('目前進度不會保存，返回後可以重新發牌。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('繼續遊戲')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('返回大廳')),
                ],
              ));
      if (confirmed != true) return;
    }
    if (mounted) Navigator.pop(context);
  }

  String player(int i) => '${i + 1} 號 · ${game.players[i]}';
  String roleArt(int i) => Assets.role(game.roles[i], variants[i]);

  bool get isPrivate => const [
        GamePhase.identity,
        GamePhase.vote,
        GamePhase.quest,
        GamePhase.assassination
      ].contains(game.phase);

  int get privateActor => switch (game.phase) {
        GamePhase.quest => game.questActor,
        GamePhase.assassination => game.roles.indexOf(Role.assassin),
        _ => game.actor,
      };

  /// When every vote card in front of the seats has been turned over.
  int get _votesShownMs => 760 + 120 * game.players.length + 500;

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) leave();
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: WoodTable(
            child: SafeArea(
              child: LayoutBuilder(builder: (context, c) {
                final s =
                    min(c.maxHeight / 390, c.maxWidth / 800).clamp(.72, 2.2);
                _s = s;
                final secret = isPrivate && !_interlude && !_dealing;
                final questShow =
                    game.phase == GamePhase.questResult && !_interlude;
                final endShow = game.phase == GamePhase.finished && !_interlude;
                final note = _announcement;
                return Shaker(
                  key: _shaker,
                  child: Stack(children: [
                    Positioned.fill(child: _table(s)),
                    Positioned.fill(child: _props(s)),
                    const Positioned.fill(
                        child: Particles(kind: ParticleKind.dust, count: 26)),
                    if (note != null)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Announcement(
                              key: ValueKey(_announceId),
                              title: note.$1,
                              subtitle: note.$2,
                              delay: _ms(note.$3),
                              scale: s),
                        ),
                      ),
                    Positioned.fill(
                      child: BlurScrim(
                          visible: questShow,
                          sigma: 8,
                          dim: .58,
                          child: questShow ? _questReveal(s, c) : null),
                    ),
                    Positioned.fill(
                      child: BlurScrim(
                          visible: endShow,
                          sigma: 8,
                          dim: .66,
                          child: endShow ? _ending(s, c) : null),
                    ),
                    Positioned.fill(
                      child: BlurScrim(
                          visible: secret,
                          child: secret ? _privateLayer(s, c) : null),
                    ),
                    Positioned.fill(child: FlightLayer(key: _flights)),
                  ]),
                );
              }),
            ),
          ),
        ),
      );

  // ───────────────────────── table ─────────────────────────

  Widget _table(double s) {
    final n = game.players.length;
    final half = (n + 1) ~/ 2;
    final left = [for (var i = half - 1; i >= 0; i--) i];
    final right = [for (var i = half; i < n; i++) i];
    Widget column(List<int> seats, bool tokensOnRight) => Container(
          width: 192 * s,
          // leave room for the leader crown that overhangs the plaque
          padding: EdgeInsets.only(
              left: tokensOnRight ? 12 * s : 0,
              right: tokensOnRight ? 0 : 12 * s,
              top: 10 * s),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final (row, i) in seats.indexed)
                // players take their seats
                Appear(
                  key: ValueKey('in$i'),
                  delay: _ms(120 + 70 * row),
                  duration: _ms(460),
                  offset: Offset(tokensOnRight ? -60 * s : 60 * s, 0),
                  child: _seat(i, s, tokensOnRight),
                ),
            ],
          ),
        );
    return Row(children: [
      column(left, true),
      Expanded(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8 * s),
          child: Appear(
            duration: _ms(520),
            offset: Offset.zero,
            scaleFrom: .94,
            child: LeatherMat(
              radius: 20 * s,
              child: Padding(
                padding: EdgeInsets.fromLTRB(10 * s, 8 * s, 10 * s, 8 * s),
                child: Column(children: [
                  _banner(s),
                  SizedBox(height: 6 * s),
                  Expanded(
                    child: Center(
                      child: QuestBoard(
                          game: game,
                          onImpact: () {
                            HapticFeedback.heavyImpact();
                            _shaker.currentState?.shake(4);
                          }),
                    ),
                  ),
                  SizedBox(height: 6 * s),
                  _actionBar(s),
                ]),
              ),
            ),
          ),
        ),
      ),
      column(right, false),
    ]);
  }

  Widget _seat(int i, double s, bool tokensOnRight) {
    final phase = game.phase;
    final onTeam = switch (phase) {
      GamePhase.team => selected.contains(i) && !_shieldLanding.contains(i),
      GamePhase.vote ||
      GamePhase.voteResult ||
      GamePhase.quest ||
      GamePhase.questResult =>
        game.team.contains(i),
      _ => false,
    };
    final vote = _voteLanding.contains(i)
        ? SeatVote.none
        : switch (phase) {
            GamePhase.vote => i < game.actor ? SeatVote.hidden : SeatVote.none,
            GamePhase.voteResult =>
              game.votes[i] ? SeatVote.approve : SeatVote.reject,
            _ => SeatVote.none,
          };
    final canPick = phase == GamePhase.team &&
        (selected.contains(i) || selected.length < game.requiredTeam);
    return SeatPlate(
      key: ValueKey('seat$i'),
      number: i + 1,
      name: game.players[i],
      scale: s,
      tokensOnRight: tokensOnRight,
      isLeader:
          i == game.leader && phase != GamePhase.finished && !_crownFlying,
      onTeam: onTeam,
      highlight: (phase == GamePhase.team && selected.contains(i)) ||
          (isPrivate && i == privateActor),
      vote: vote,
      // one after another around the table, once the last card has landed
      voteDelay: _ms(760 + 120 * i),
      bump: _bumps[i],
      plateKey: _plateKeys[i],
      crownKey: _crownKeys[i],
      shieldKey: _shieldKeys[i],
      voteKey: _voteKeys[i],
      onTap: canPick ? () => _toggleSeat(i) : null,
    );
  }

  /// Loose pieces lying on the board: the deck being dealt, the pile of
  /// quest cards played so far, and the verdict stamped on a vote.
  Widget _props(double s) {
    final played = switch (game.phase) {
      GamePhase.quest => game.actor,
      GamePhase.questResult => _interlude ? game.team.length : 0,
      _ => 0,
    };
    final pile = max(0, played - _pileLanding);
    final approved =
        game.phase == GamePhase.voteResult ? game.teamApproved : false;
    final stampColor = approved ? const Color(0xFFFFE3A3) : _evil;
    return IgnorePointer(
      child: Align(
        alignment: const Alignment(0, -.36),
        child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                key: _pileKey,
                width: 34 * s,
                height: 51 * s,
                child: Stack(clipBehavior: Clip.none, children: [
                  for (var j = 0; j < pile; j++)
                    Transform.rotate(
                      angle: ((j * 37) % 11 - 5) * .045,
                      child: CardBack(
                          width: 34 * s, elevation: 3, deck: CardDeck.quest),
                    ),
                ]),
              ),
              AnimatedOpacity(
                duration: _ms(260),
                opacity: _dealing ? 1 : 0,
                child: SizedBox(
                  key: _deckKey,
                  width: 46 * s,
                  height: 69 * s,
                  child: Stack(clipBehavior: Clip.none, children: [
                    for (var j = 0; j < 3; j++)
                      Positioned(
                        left: -j * 1.6 * s,
                        top: -j * 1.6 * s,
                        child: CardBack(width: 46 * s, elevation: 2.0 + j * 2),
                      ),
                  ]),
                ),
              ),
              if (game.phase == GamePhase.voteResult)
                StampIn(
                  key: ValueKey('v${game.history.length}.${game.rejections}'),
                  delay: _ms(_votesShownMs),
                  angle: -.1,
                  onLand: () {
                    HapticFeedback.heavyImpact();
                    _shaker.currentState?.shake(approved ? 3 : 6);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 20 * s, vertical: 4 * s),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(8 * s),
                      border: Border.all(color: stampColor, width: 3 * s),
                      boxShadow: [
                        BoxShadow(
                            color: stampColor.withValues(alpha: .5),
                            blurRadius: 18 * s)
                      ],
                    ),
                    child: Text(approved ? '通過' : '否決',
                        style: TextStyle(
                            fontSize: 34 * s,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 10 * s,
                            color: stampColor)),
                  ),
                ),
            ]),
      ),
    );
  }

  Widget _banner(double s) {
    final (title, sub) = switch (game.phase) {
      GamePhase.identity => ('身分確認', '依序將手機交給每位玩家查看身分'),
      GamePhase.assassination => ('刺殺梅林', '正義已完成三次任務，刺客的最後機會'),
      GamePhase.finished => ('遊戲結束', ''),
      GamePhase.questResult => ('第 ${game.history.length} 次遠征', '結果揭曉'),
      _ => (
          '第 ${game.questNumber} 次遠征',
          '隊長 ${player(game.leader)}　·　派出 ${game.requiredTeam} 人'
              '${game.failsRequired == 2 ? '　·　需兩張失敗' : ''}'
        ),
    };
    return Row(children: [
      _roundIcon(Icons.arrow_back, s, leave, '返回大廳'),
      Expanded(
        child: AnimatedSwitcher(
          duration: _ms(380),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
                position: Tween(begin: const Offset(0, .4), end: Offset.zero)
                    .animate(a),
                child: child),
          ),
          child: Column(
              key: ValueKey('$title|$sub'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 18 * s,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 3,
                        color: AvalonTheme.gold,
                        shadows: const [Shadow(blurRadius: 6)])),
                if (sub.isNotEmpty)
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11.5 * s, color: const Color(0xFFD9CFB8))),
              ]),
        ),
      ),
      SizedBox(width: 34 * s),
    ]);
  }

  Widget _roundIcon(IconData icon, double s, VoidCallback onTap, String tip) =>
      Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: onTap,
          child: Pressable(
            child: Container(
              width: 34 * s,
              height: 34 * s,
              decoration: plaqueDecoration(radius: 17 * s),
              child: Icon(icon, size: 18 * s, color: AvalonTheme.gold),
            ),
          ),
        ),
      );

  Widget _actionBar(double s) {
    Widget bar(String hint, Widget button) => Row(children: [
          Expanded(
            child: Text(hint,
                maxLines: 2,
                style: TextStyle(
                    fontSize: 12.5 * s,
                    height: 1.4,
                    color: const Color(0xFFE8DCC0))),
          ),
          button,
        ]);
    switch (game.phase) {
      case GamePhase.team:
        return bar(
            '隊長點選座位，挑選 ${game.requiredTeam} 名隊員',
            TableButton(
              '提案並開始投票（${selected.length}/${game.requiredTeam}）',
              scale: s,
              onPressed: selected.length == game.requiredTeam
                  ? () => act(() => game.proposeTeam(selected.toList()))
                  : null,
            ));
      case GamePhase.voteResult:
        final yes = game.votes.where((v) => v).length;
        // the count is only shown once every card has been turned over
        return Appear(
          key: ValueKey('vr${game.history.length}.${game.rejections}'),
          delay: _ms(_votesShownMs + 250),
          child: bar(
              '贊成 $yes · 反對 ${game.players.length - yes}　—　'
              '${game.teamApproved ? '組隊通過' : '組隊遭否決（需超過半數贊成）'}',
              TableButton(game.teamApproved ? '開始秘密執行任務' : '繼續',
                  scale: s, onPressed: () => act(game.continueVote))),
        );
      default:
        return SizedBox(height: 36 * s);
    }
  }

  // ───────────────────── private (secret) layer ─────────────────────

  Widget _privateLayer(double s, BoxConstraints c) {
    final actor = privateActor;
    final action = switch (game.phase) {
      GamePhase.identity => '查看身分',
      GamePhase.vote => '投下組隊票',
      GamePhase.quest => '執行任務',
      _ => '選擇刺殺目標',
    };
    final content = !revealed
        ? _handoff(actor, action, s)
        : switch (game.phase) {
            GamePhase.identity => _identity(actor, s, c),
            GamePhase.vote => _secretVote(s, c),
            GamePhase.quest => _secretQuest(actor, s, c),
            _ => _assassinate(s),
          };
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.all(16 * s),
      child: AnimatedSwitcher(
        duration: _ms(380),
        switchInCurve: Curves.easeOut,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: ScaleTransition(
              scale: Tween(begin: .95, end: 1.0).animate(a), child: child),
        ),
        child: KeyedSubtree(
            key: ValueKey('${game.phase}$actor$revealed'), child: content),
      ),
    );
  }

  TextStyle _t(double size, double s,
          {Color color = _ink,
          FontWeight weight = FontWeight.normal,
          double height = 1.5}) =>
      TextStyle(
          fontSize: size * s, color: color, fontWeight: weight, height: height);

  Widget _handoff(int actor, String action, double s) {
    final deck = game.phase == GamePhase.quest ? CardDeck.quest : CardDeck.role;
    Widget line(int i, Widget child) => Appear(
        delay: _ms(100 + 70 * i), offset: Offset(18 * s, 0), child: child);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Appear(
          duration: _ms(520),
          offset: Offset(0, 34 * s),
          scaleFrom: .8,
          child: Floaty(
            amplitude: 3 * s,
            child: SizedBox(
              width: 150 * s,
              height: 190 * s,
              child: Stack(alignment: Alignment.center, children: [
                Transform.rotate(
                    angle: -.12,
                    child: CardBack(width: 100 * s, elevation: 8, deck: deck)),
                Transform.rotate(
                    angle: .08,
                    child: CardBack(width: 100 * s, elevation: 10, deck: deck)),
              ]),
            ),
          ),
        ),
        SizedBox(width: 28 * s),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 360 * s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              line(0,
                  Text('請將手機交給', style: _t(15, s, color: AvalonTheme.muted))),
              line(
                  1,
                  Text(player(actor),
                      style: _t(30, s,
                          color: AvalonTheme.gold,
                          weight: FontWeight.bold,
                          height: 1.3))),
              SizedBox(height: 8 * s),
              line(2, Text('接下來要$action，請確認只有本人能看見畫面。', style: _t(13, s))),
              line(
                  3,
                  Text('其他玩家請移開視線。',
                      style: _t(13, s, color: AvalonTheme.muted))),
              SizedBox(height: 18 * s),
              line(
                  4,
                  TableButton('我是本人，開啟秘密畫面', scale: s, onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      revealed = true;
                      _choiceKeys = {true: GlobalKey(), false: GlobalKey()};
                    });
                  })),
            ],
          ),
        ),
      ],
    );
  }

  Widget _identity(int actor, double s, BoxConstraints c) {
    final role = game.roles[actor];
    final cardW = min((c.maxHeight - 40 * s) * cardAspect, c.maxWidth * .32);
    final color = role.isEvil ? _evil : _good;
    const flipAt = 350, flipMs = 900, shown = flipAt + flipMs;
    Widget line(int i, Widget child) => Appear(
        delay: _ms(shown - 250 + 110 * i),
        offset: Offset(20 * s, 0),
        child: child);
    return Stack(alignment: Alignment.center, children: [
      Positioned.fill(
        child: Appear(
          delay: _ms(shown - 300),
          duration: _ms(1200),
          offset: Offset.zero,
          child: Particles(
              kind: role.isEvil ? ParticleKind.ember : ParticleKind.spark,
              count: 22,
              seed: actor + 3),
        ),
      ),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          // light bursts out as the card turns
          Positioned.fill(
            child: GlowBurst(
                color: color,
                size: cardW * 3.4,
                delay: _ms(flipAt + flipMs ~/ 2 - 60)),
          ),
          Floaty(
            amplitude: 2 * s,
            tilt: true,
            child: FlipCard(
              faceUp: !_hiding,
              flipOnMount: true,
              delay: _ms(flipAt),
              duration: _ms(flipMs),
              back: CardBack(width: cardW, elevation: 14),
              front: ShineSweep(
                delay: _ms(flipMs ~/ 2 - 80),
                radius: cardW * .06,
                child: GameCard(roleArt(actor), width: cardW, elevation: 14),
              ),
            ),
          ),
        ]),
        SizedBox(width: 32 * s),
        AnimatedOpacity(
          duration: _ms(220),
          opacity: _hiding ? 0 : 1,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 330 * s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                line(
                    0,
                    Text(player(actor),
                        style: _t(13, s, color: AvalonTheme.muted))),
                line(
                    1,
                    Text(role.label,
                        style: TextStyle(
                            fontSize: 34 * s,
                            height: 1.25,
                            fontWeight: FontWeight.bold,
                            color: color,
                            shadows: [
                              Shadow(
                                  color: color.withValues(alpha: .7),
                                  blurRadius: 18 * s)
                            ]))),
                line(
                    2,
                    Text(
                        role.isEvil
                            ? '邪惡陣營 · 讓任務失敗或找出梅林'
                            : '正義陣營 · 完成三次任務並保護梅林',
                        style: _t(13, s, color: color.withValues(alpha: .85)))),
                SizedBox(height: 12 * s),
                line(
                    3,
                    Container(
                      padding: EdgeInsets.all(12 * s),
                      decoration: plaqueDecoration(radius: 10 * s),
                      child: Text(game.knowledge(actor),
                          style: _t(13.5, s, height: 1.7)),
                    )),
                SizedBox(height: 18 * s),
                line(
                    4,
                    TableButton('記住了，隱藏並交給下一位', scale: s, onPressed: () {
                      if (_hiding) return;
                      // the card is turned face down before the phone
                      // changes hands
                      HapticFeedback.selectionClick();
                      setState(() => _hiding = true);
                      _after(_ms(400), () => act(game.confirmIdentity));
                    })),
              ],
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _choiceRow(
      double s,
      BoxConstraints c,
      String title,
      String sub,
      List<(bool, String, String, bool)> options,
      String confirm,
      CardDeck deck,
      VoidCallback onConfirm) {
    final cardW = min((c.maxHeight - 200 * s) * cardAspect, 150 * s);
    // scaleDown keeps it on screen even on unusually short displays
    return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Appear(
            offset: Offset(0, -10 * s),
            child: Column(children: [
              Text(title,
                  style: _t(20, s,
                      color: AvalonTheme.gold, weight: FontWeight.bold)),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: c.maxWidth * .8),
                child: Text(sub,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: _t(12.5, s)),
              ),
            ]),
          ),
          SizedBox(height: 14 * s),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (i, (value, asset, label, enabled)) in options.indexed)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14 * s),
                child: _ChoiceCard(
                  cardKey: _choiceKeys[value]!,
                  index: i,
                  asset: asset,
                  label: label,
                  deck: deck,
                  width: cardW,
                  scale: s,
                  selected: choice == value,
                  dimmed: choice != null && choice != value,
                  committing: _committing,
                  enabled: enabled,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => choice = value);
                  },
                ),
              ),
          ]),
          SizedBox(height: 14 * s),
          AnimatedOpacity(
            duration: _ms(200),
            opacity: _committing ? 0 : 1,
            child: Appear(
              delay: _ms(380),
              child: TableButton(confirm,
                  scale: s,
                  onPressed: choice == null || _committing ? null : onConfirm),
            ),
          ),
        ]));
  }

  Widget _secretVote(double s, BoxConstraints c) {
    final seat = game.actor;
    return _choiceRow(
      s,
      c,
      '${player(seat)}　投下組隊票',
      '提案隊伍：${game.team.map((i) => '${i + 1} 號 ${game.players[i]}').join('、')}',
      [
        (true, Assets.voteApprove, '贊成', true),
        (false, Assets.voteReject, '反對', true),
      ],
      '蓋牌投出',
      CardDeck.role,
      // the card is laid face down in front of the voter's seat
      () => _commit(() => game.vote(choice!),
          deck: CardDeck.role,
          target: _voteKeys[seat],
          onLaunch: () => _voteLanding.add(seat),
          onLand: () {
            _voteLanding.remove(seat);
            _bumps[seat]++;
          }),
    );
  }

  Widget _secretQuest(int actor, double s, BoxConstraints c) {
    final evil = game.roles[actor].isEvil;
    return _choiceRow(
      s,
      c,
      '${player(actor)}　執行任務',
      evil ? '邪惡玩家可以自由選擇。結果只會公布總失敗張數。' : '正義玩家只能打出「任務成功」。',
      [
        (true, Assets.questSuccess, '任務成功', true),
        (false, Assets.questFail, '破壞任務', evil),
      ],
      '蓋牌打出',
      CardDeck.quest,
      // the card joins the face-down pile on the board
      () => _commit(() => game.playQuest(choice!),
          deck: CardDeck.quest,
          target: _pileKey,
          onLaunch: () => _pileLanding++,
          onLand: () => _pileLanding = max(0, _pileLanding - 1)),
    );
  }

  Widget _assassinate(double s) {
    final targets = [
      for (var i = 0; i < game.players.length; i++)
        if (!game.roles[i].isEvil) i
    ];
    return Stack(alignment: Alignment.center, children: [
      const Positioned.fill(
          child: Particles(kind: ParticleKind.ember, count: 18, seed: 21)),
      Column(mainAxisSize: MainAxisSize.min, children: [
        Appear(
          offset: Offset(0, -10 * s),
          child: Column(children: [
            Text('${player(privateActor)}　選擇刺殺目標',
                style: _t(20, s, color: _evil, weight: FontWeight.bold)),
            Text('與邪惡同伴討論後，選出你認為的梅林。', style: _t(12.5, s)),
          ]),
        ),
        SizedBox(height: 16 * s),
        Wrap(
          spacing: 12 * s,
          runSpacing: 10 * s,
          alignment: WrapAlignment.center,
          children: [
            for (final (row, i) in targets.indexed)
              Appear(
                delay: _ms(150 + 70 * row),
                scaleFrom: .9,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() => selected
                      ..clear()
                      ..add(i));
                  },
                  child: Pressable(
                    child: AnimatedScale(
                      duration: _ms(200),
                      scale: selected.contains(i) ? 1.08 : 1,
                      child: AnimatedContainer(
                        duration: _ms(200),
                        padding: EdgeInsets.symmetric(
                            horizontal: 16 * s, vertical: 10 * s),
                        decoration: plaqueDecoration(
                                highlight: selected.contains(i), radius: 10 * s)
                            .copyWith(
                                border: selected.contains(i)
                                    ? Border.all(color: _evil, width: 2)
                                    : null,
                                boxShadow: selected.contains(i)
                                    ? [
                                        BoxShadow(
                                            color: _evil.withValues(alpha: .6),
                                            blurRadius: 18 * s)
                                      ]
                                    : null),
                        child: Text(player(i),
                            style: _t(14, s,
                                color: selected.contains(i) ? _evil : _ink)),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        SizedBox(height: 18 * s),
        Appear(
          delay: _ms(450),
          child: TableButton('確認刺殺',
              scale: s,
              onPressed: selected.length == 1
                  ? () {
                      final target = selected.single;
                      _assassinTarget = target;
                      act(() => game.assassinate(target));
                    }
                  : null),
        ),
      ]),
    ]);
  }

  // ───────────────────── public reveals ─────────────────────

  void _onReveal(RevealItem item) {
    if (item.shock) {
      HapticFeedback.heavyImpact();
      _shaker.currentState?.shake(9);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  Widget _questReveal(double s, BoxConstraints c) {
    final q = game.history.last;
    final n = questOrder.length;
    final cardW = min((c.maxHeight - 190 * s) * cardAspect / 1.2,
        (c.maxWidth - 80 * s) / n - 18 * s);
    return Padding(
      padding: EdgeInsets.all(10 * s),
      child: CardReveal(
        key: ValueKey('quest${game.history.length}'),
        cardWidth: cardW,
        scale: s,
        caption: '第 ${game.history.length} 次任務　·　洗勻後逐張翻開',
        items: [
          for (final success in questOrder)
            RevealItem(
              glow: success ? const Color(0xFFFFD98A) : _evil,
              shock: !success,
              back: (w) =>
                  CardBack(width: w, elevation: 10, deck: CardDeck.quest),
              front: (w) => GameCard(
                  success ? Assets.questSuccess : Assets.questFail,
                  width: w,
                  elevation: 10),
            ),
        ],
        verdict: q.succeeded ? '任務成功' : '任務失敗',
        verdictColor: q.succeeded ? _good : _evil,
        particles: q.succeeded ? ParticleKind.spark : ParticleKind.ember,
        detail: '收到 ${q.team.length - q.fails} 張成功、${q.fails} 張失敗',
        button: '繼續議會',
        onReveal: _onReveal,
        onVerdict: () {
          HapticFeedback.heavyImpact();
          if (!q.succeeded) _shaker.currentState?.shake(7);
        },
        // back to a clear table: the score marker is dropped on the board
        onContinue: () => act(game.continueQuest, interlude: true),
      ),
    );
  }

  Widget _ending(double s, BoxConstraints c) {
    final target = _assassinTarget;
    final showStrike = target != null && !_assassinShown;
    return AnimatedSwitcher(
      duration: _ms(450),
      child: showStrike
          ? _assassinReveal(target, s, c)
          : KeyedSubtree(
              key: const ValueKey('roles'), child: _finalReveal(s, c)),
    );
  }

  /// The assassin's target turns their card over: Merlin, or not?
  Widget _assassinReveal(int target, double s, BoxConstraints c) {
    final hit = game.roles[target] == Role.merlin;
    final cardW = min((c.maxHeight - 210 * s) * cardAspect / 1.2, 170 * s);
    return Padding(
      key: const ValueKey('strike'),
      padding: EdgeInsets.all(10 * s),
      child: CardReveal(
        cardWidth: cardW,
        scale: s,
        shuffle: false,
        caption: '刺客出手　·　目標是 ${player(target)}',
        items: [
          RevealItem(
            glow: hit ? _evil : _good,
            shock: hit,
            back: (w) => CardBack(width: w, elevation: 12),
            front: (w) => GameCard(roleArt(target), width: w, elevation: 12),
          ),
        ],
        verdict: hit ? '梅林遇刺' : '刺殺失敗',
        verdictColor: hit ? _evil : _good,
        particles: hit ? ParticleKind.ember : ParticleKind.spark,
        detail: hit ? '邪惡陣營逆轉獲勝' : '梅林安然無恙，正義陣營獲勝',
        button: '揭曉全員身分',
        onReveal: _onReveal,
        onVerdict: () {
          HapticFeedback.heavyImpact();
          if (hit) _shaker.currentState?.shake(8);
        },
        onContinue: () {
          HapticFeedback.mediumImpact();
          setState(() => _assassinShown = true);
        },
      ),
    );
  }

  Widget _finalReveal(double s, BoxConstraints c) {
    final n = game.players.length;
    final perRow = n <= 5 ? n : (n + 1) ~/ 2;
    final rows = (n / perRow).ceil();
    final cardW = min(((c.maxHeight - 150 * s) / rows - 20 * s) * cardAspect,
        (c.maxWidth - 60 * s) / perRow - 14 * s);
    final evilWon = game.winner == '邪惡';
    final color = evilWon ? _evil : _good;
    const firstFlip = 950, step = 220;
    Widget seatCard(int i) => Padding(
          padding: EdgeInsets.symmetric(horizontal: 7 * s, vertical: 3 * s),
          child: SizedBox(
            width: cardW,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Appear(
                delay: _ms(250 + 60 * i),
                offset: Offset(0, 30 * s),
                scaleFrom: .8,
                child: FlipCard(
                  faceUp: true,
                  flipOnMount: true,
                  delay: _ms(firstFlip + step * i),
                  back: CardBack(width: cardW, elevation: 6),
                  front: ShineSweep(
                    delay: _ms(300),
                    radius: cardW * .06,
                    child: GameCard(roleArt(i), width: cardW, elevation: 6),
                  ),
                ),
              ),
              SizedBox(height: 3 * s),
              Appear(
                delay: _ms(firstFlip + step * i + 350),
                offset: Offset(0, 6 * s),
                child: Text('${i + 1}. ${game.players[i]}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _t(11, s, height: 1.2)),
              ),
            ]),
          ),
        );
    return Stack(fit: StackFit.expand, children: [
      Particles(
          kind: evilWon ? ParticleKind.ember : ParticleKind.spark, count: 46),
      Padding(
        padding: EdgeInsets.all(10 * s),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              StampIn(
                delay: _ms(150),
                onLand: () {
                  HapticFeedback.heavyImpact();
                  _shaker.currentState?.shake(5);
                },
                child: Text('${game.winner}陣營獲勝',
                    style: TextStyle(
                        fontSize: 28 * s,
                        height: 1.2,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 4 * s,
                        color: color,
                        shadows: [
                          Shadow(
                              color: color.withValues(alpha: .8),
                              blurRadius: 22 * s),
                          const Shadow(blurRadius: 4),
                        ])),
              ),
              Appear(
                  delay: _ms(650),
                  child: Text(game.result, style: _t(12.5, s))),
              SizedBox(height: 10 * s),
              for (var r = 0; r < rows; r++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = r * perRow; i < min(n, (r + 1) * perRow); i++)
                    seatCard(i),
                ]),
              SizedBox(height: 12 * s),
              Appear(
                delay: _ms(firstFlip + step * n + 500),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  TableButton('相同配置，再玩一局',
                      scale: s, onPressed: () => act(_newGame)),
                  SizedBox(width: 14 * s),
                  TableButton('返回大廳',
                      scale: s, primary: false, onPressed: leave),
                ]),
              ),
            ]),
          ),
        ),
      ),
    ]);
  }
}

/// A card held in hand. It is dealt in from below, lifts and glows when
/// picked, and is turned face down when the choice is confirmed.
class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.cardKey,
    required this.index,
    required this.asset,
    required this.label,
    required this.deck,
    required this.width,
    required this.scale,
    required this.selected,
    required this.dimmed,
    required this.committing,
    required this.enabled,
    required this.onTap,
  });
  final GlobalKey cardKey;
  final int index;
  final String asset;
  final String label;
  final CardDeck deck;
  final double width;
  final double scale;
  final bool selected;
  final bool dimmed;
  final bool committing;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    Widget card = FlipCard(
      faceUp: !(committing && selected),
      back: CardBack(width: width, deck: deck, elevation: 16),
      front: GameCard(asset, width: width, elevation: selected ? 16 : 8),
    );
    if (!enabled) {
      card = Stack(alignment: Alignment.center, children: [
        ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            .33, .33, .33, 0, 0, //
            .33, .33, .33, 0, 0, //
            .33, .33, .33, 0, 0, //
            0, 0, 0, .55, 0,
          ]),
          child: card,
        ),
        Icon(Icons.lock, color: Colors.white70, size: 34 * scale),
      ]);
    }
    final glow = selected && !committing;
    return Appear(
      delay: Duration(milliseconds: 120 + 130 * index),
      duration: const Duration(milliseconds: 520),
      offset: Offset(0, 80 * scale),
      scaleFrom: .85,
      turnFrom: index.isEven ? -.2 : .2,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: committing && !selected ? 0 : (dimmed ? .6 : 1),
        child: GestureDetector(
          onTap: enabled && !committing ? onTap : null,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              transform:
                  Matrix4.translationValues(0, selected ? -14 * scale : 0, 0),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(width * .06),
                boxShadow: glow
                    ? [
                        BoxShadow(
                            color: AvalonTheme.gold.withValues(alpha: .7),
                            blurRadius: 22 * scale,
                            spreadRadius: 2 * scale)
                      ]
                    : null,
              ),
              child: AnimatedScale(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutBack,
                scale: selected ? 1.06 : 1,
                child: KeyedSubtree(key: cardKey, child: card),
              ),
            ),
            SizedBox(height: 6 * scale),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: committing ? 0 : 1,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13 * scale,
                      fontWeight: FontWeight.bold,
                      color: selected ? AvalonTheme.gold : Colors.white70)),
            ),
          ]),
        ),
      ),
    );
  }
}

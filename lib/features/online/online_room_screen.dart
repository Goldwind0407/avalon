import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_model.dart';
import '../game/game_screen.dart';
import '../game/game_session.dart';
import '../lobby/room_model.dart';
import 'online_session.dart';

/// A room before (and between) games: who is in, which roles are used.
/// When the host deals, every phone moves to the table automatically.
class OnlineRoomScreen extends StatefulWidget {
  const OnlineRoomScreen(
      {super.key, required this.code, required this.uid, this.session});
  final String code;
  final String uid;

  /// For tests; normally the screen connects to Firebase itself.
  final OnlineGameSession? session;

  @override
  State<OnlineRoomScreen> createState() => _OnlineRoomScreenState();
}

class _OnlineRoomScreenState extends State<OnlineRoomScreen> {
  late final OnlineGameSession session =
      widget.session ?? OnlineGameSession.connect(widget.code, widget.uid);
  bool _tableOpen = false;

  /// The deal the player walked away from; they are not pulled back into it.
  int _leftGen = -1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    session.addListener(_onRoomChanged);
  }

  @override
  void dispose() {
    session.removeListener(_onRoomChanged);
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  void _onRoomChanged() {
    final room = session.room;
    if (room != null && room.inGame && !_tableOpen && room.gen != _leftGen) {
      _openTable();
    }
  }

  Future<void> _openTable() async {
    _tableOpen = true;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => GameScreen.online(session: session)));
    if (!mounted) return;
    setState(() {
      _tableOpen = false;
      _leftGen = session.generation;
    });
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } on GameMoveException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leave() async {
    final room = session.room;
    // in the lobby the seat is given up; during a game it is kept so the
    // player can come back with the same code
    if (room != null && room.status == 'lobby') {
      await _run(session.leave);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          body: FantasyBackground(
            child: SafeArea(
              child: ListenableBuilder(
                listenable: session,
                builder: (context, _) => _body(),
              ),
            ),
          ),
        ),
      );

  Widget _message(String text) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(text, style: const TextStyle(color: AvalonTheme.muted)),
          const SizedBox(height: 16),
          SizedBox(
            width: 180,
            child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('返回')),
          ),
        ]),
      );

  Widget _body() {
    if (session.closed) return _message('這個房間已經關閉了');
    if (session.error != null) return _message('無法讀取房間，可能已不在房間內');
    final room = session.room;
    if (room == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final host = session.isHost;
    final n = room.players.length;
    final issue = onlineSetupIssue(n, room.optionalRoles);
    final finished = room.inGame && session.phase == GamePhase.finished;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(children: [
        Row(children: [
          IconButton(
              tooltip: '離開房間',
              onPressed: _busy ? null : _leave,
              icon: const Icon(Icons.arrow_back),
              color: AvalonTheme.gold),
          const SizedBox(width: 4),
          const Text('房號',
              style: TextStyle(color: AvalonTheme.muted, fontSize: 13)),
          const SizedBox(width: 8),
          SelectableText(room.code,
              key: const ValueKey('roomCode'),
              style: const TextStyle(
                  fontSize: 26,
                  letterSpacing: 6,
                  fontWeight: FontWeight.bold,
                  color: AvalonTheme.gold)),
          IconButton(
              tooltip: '複製房號',
              icon: const Icon(Icons.copy, size: 18),
              color: AvalonTheme.muted,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: room.code));
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(const SnackBar(content: Text('已複製房號')));
              }),
          const Spacer(),
          Text(host ? '你是房主' : '等待房主開始',
              style: const TextStyle(color: AvalonTheme.muted, fontSize: 12)),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 6, child: _seats(room)),
            const SizedBox(width: 10),
            Expanded(flex: 5, child: _roles(room, host)),
          ]),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Text(
              room.inGame
                  ? (finished ? '對局已結束' : '對局進行中')
                  : issue ??
                      '正義 ${n - Room.evilCount(n)} 人・邪惡 ${Room.evilCount(n)} 人，其他名額自動補齊',
              style: TextStyle(
                  fontSize: 12,
                  color: !room.inGame && issue != null
                      ? Colors.orangeAccent
                      : AvalonTheme.muted),
            ),
          ),
          if (room.inGame) ...[
            if (host && finished) ...[
              SizedBox(
                height: 42,
                child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: Size.zero),
                    onPressed: _busy ? null : () => _run(session.backToLobby),
                    child: const Text('回到大廳調整')),
              ),
              const SizedBox(width: 10),
            ],
            SizedBox(
              width: 170,
              height: 42,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(minimumSize: Size.zero),
                onPressed: _openTable,
                icon: const Icon(Icons.table_restaurant),
                label: const Text('回到對局'),
              ),
            ),
          ] else if (host)
            SizedBox(
              width: 170,
              height: 42,
              child: ElevatedButton.icon(
                key: const ValueKey('startOnline'),
                style: ElevatedButton.styleFrom(minimumSize: Size.zero),
                onPressed:
                    issue == null && !_busy ? () => _run(session.start) : null,
                icon: const Icon(Icons.play_arrow),
                label: const Text('開始遊戲'),
              ),
            ),
        ]),
      ]),
    );
  }

  Widget _seats(OnlineRoom room) => GoldPanel(
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionLabel('玩家（${room.players.length}/10）'),
          const SizedBox(height: 8),
          for (var row = 0; row < 5; row++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: row == 0 ? 0 : 5),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var column = 0; column < 2; column++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(left: column == 0 ? 0 : 6),
                            child: _seat(room, row * 2 + column),
                          ),
                        ),
                    ]),
              ),
            ),
        ]),
      );

  Widget _seat(OnlineRoom room, int seat) {
    if (seat >= room.players.length) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AvalonTheme.raised),
        ),
        child: const Center(
            child: Text('空位',
                style: TextStyle(color: AvalonTheme.raised, fontSize: 12))),
      );
    }
    final p = room.players[seat];
    final me = p.uid == session.uid;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: AvalonTheme.raised,
        borderRadius: BorderRadius.circular(9),
        border: me ? Border.all(color: AvalonTheme.gold) : null,
      ),
      child: Row(children: [
        Text('${seat + 1}',
            style: const TextStyle(
                color: AvalonTheme.gold, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13)),
        ),
        if (p.uid == room.hostUid)
          const Tooltip(
              message: '房主',
              child: Icon(Icons.workspace_premium,
                  size: 16, color: AvalonTheme.gold)),
        if (me)
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('你',
                style: TextStyle(fontSize: 11, color: AvalonTheme.gold)),
          ),
      ]),
    );
  }

  Widget _roles(OnlineRoom room, bool host) {
    final editable = host && !room.inGame && !_busy;
    final options = [
      (Role.merlin, '正義・固定', true),
      (Role.assassin, '邪惡・固定', true),
      for (final r in optionalRoles) (r, r.isEvil ? '邪惡' : '正義', false),
    ];
    return GoldPanel(
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionLabel(host ? '角色配置' : '角色配置（房主設定）'),
        const SizedBox(height: 8),
        for (var row = 0; row < 3; row++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: row == 0 ? 0 : 5),
              child: Row(children: [
                for (var column = 0; column < 2; column++)
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: column == 0 ? 0 : 6),
                      child: () {
                        final (role, side, fixed) = options[row * 2 + column];
                        final active =
                            fixed || room.optionalRoles.contains(role);
                        return Material(
                          color: active
                              ? AvalonTheme.violet.withValues(alpha: .3)
                              : AvalonTheme.raised,
                          borderRadius: BorderRadius.circular(9),
                          child: InkWell(
                            key: ValueKey('onlineRole${role.name}'),
                            borderRadius: BorderRadius.circular(9),
                            onTap: fixed || !editable
                                ? null
                                : () {
                                    final next = {...room.optionalRoles};
                                    active ? next.remove(role) : next.add(role);
                                    _run(() => session.setRoles(next));
                                  },
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(children: [
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(role.label,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: active
                                                  ? AvalonTheme.gold
                                                  : Colors.white)),
                                      Text(side,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AvalonTheme.muted)),
                                    ],
                                  ),
                                ),
                                Icon(
                                    active
                                        ? Icons.check_circle
                                        : Icons.circle_outlined,
                                    size: 16,
                                    color: active
                                        ? AvalonTheme.gold
                                        : AvalonTheme.muted),
                              ]),
                            ),
                          ),
                        );
                      }(),
                    ),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}

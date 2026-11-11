import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../game/game_model.dart';
import '../game/game_screen.dart';
import '../game/game_session.dart';
import '../game/discussion_widgets.dart';
import '../game/expansion_widgets.dart';
import '../lobby/role_presets.dart';
import '../lobby/room_model.dart';
import 'online_session.dart';
import 'online_service.dart';
import 'voice/voice_controller.dart';
import 'voice/webrtc_voice_transport.dart';
import 'voice/voice_signaling.dart';
import 'voice/voice_controls.dart';

/// A room before (and between) games: who is in, which roles are used.
/// When the host deals, every phone moves to the table automatically.
class OnlineRoomScreen extends StatefulWidget {
  const OnlineRoomScreen(
      {super.key,
      required this.code,
      required this.uid,
      this.session,
      this.voice});
  final String code;
  final String uid;

  /// For tests; normally the screen connects to Firebase itself.
  final OnlineGameSession? session;
  final VoiceController? voice;

  @override
  State<OnlineRoomScreen> createState() => _OnlineRoomScreenState();
}

class _OnlineRoomScreenState extends State<OnlineRoomScreen> {
  late final OnlineGameSession session =
      widget.session ?? OnlineGameSession.connect(widget.code, widget.uid);
  late final VoiceController voice = widget.voice ??
      VoiceController(
        createTransport: () => WebRtcVoiceTransport(
            uid: widget.uid,
            signaling: FirestoreVoiceSignaling(widget.code),
            // Direct voice is the default: no TURN credentials/function call.
            // A future relay trial must be enabled explicitly when building.
            iceServers: const bool.fromEnvironment('VOICE_ENABLE_TURN')
                ? () async {
                    try {
                      final config = await OnlineService.instance
                          .call('voiceIce', {'code': widget.code});
                      return [
                        for (final server in config['iceServers'] as List)
                          Map<String, dynamic>.from(server as Map)
                      ];
                    } on GameMoveException catch (error) {
                      throw VoiceException(error.message == 'NOT FOUND'
                          ? '語音更新尚未部署，仍可繼續遊戲'
                          : error.message);
                    }
                  }
                : null),
      );
  bool _tableOpen = false;

  /// Players in the lobby when the room was last seen (presets follow it).
  int? _lastCount;
  Future<void> _presets = Future.value();
  late final AppLifecycleListener _lifecycle;

  /// This screen's route, to come back to when a game is ended for everyone.
  ModalRoute<Object?>? _route;

  /// The last room notice shown (null until the room is first loaded).
  int? _noticeSeen;

  /// The deal the player walked away from; they are not pulled back into it.
  int _leftGen = -1;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    session.addListener(_onRoomChanged);
    _updateVoiceFloor();
    // leaving the app (home screen, another app) always closes the microphone
    _lifecycle = AppLifecycleListener(onHide: voice.releaseMicrophone);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route ??= ModalRoute.of(context);
  }

  @override
  void dispose() {
    session.removeListener(_onRoomChanged);
    _lifecycle.dispose();
    if (widget.voice == null) voice.dispose();
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  void _onRoomChanged() {
    _updateVoiceFloor();
    final room = session.room;
    if (session.closed ||
        session.error != null ||
        (room != null && room.seatOf(widget.uid) < 0)) {
      voice.leave();
    }
    if (room == null || session.leaving) return;
    // someone left mid-game: the game is over, everyone comes back here
    if (!room.inGame && _tableOpen) {
      Navigator.of(context).popUntil((r) => r == _route);
    }
    _showNotice(room);
    _followPreset(room);
    if (room.inGame && !_tableOpen && room.gen != _leftGen) {
      _openTable();
    }
  }

  /// The host's phone applies the recommended roles whenever someone joins
  /// or leaves the lobby; the host can still change them afterwards.
  void _followPreset(OnlineRoom room) {
    final count = room.players.length, last = _lastCount;
    _lastCount = count;
    if (last == null || last == count || room.inGame || !session.isHost) return;
    final preset = rolePreset(count);
    if (preset == null) return;
    _presets = _presets.then((_) async {
      if (!mounted || session.room?.players.length != count) return;
      try {
        if (!setEquals(session.room!.optionalRoles, preset)) {
          await session.setRoles(preset);
        }
      } catch (_) {/* The host can still set the roles by hand. */}
    });
  }

  void _updateVoiceFloor() {
    final room = session.room;
    Set<String>? allowed;
    if (room?.inGame == true && session.discussionSettings.enabled) {
      final seat = switch (session.phase) {
        GamePhase.discussion => session.speaker,
        GamePhase.team when !session.discussionSettings.selectionFree =>
          session.leader,
        _ => null,
      };
      if (seat != null) {
        allowed = {session.playerIds[seat]};
      } else if ([
        GamePhase.identity,
        GamePhase.vote,
        GamePhase.voteResult,
        GamePhase.quest,
        GamePhase.questResult
      ].contains(session.phase)) {
        allowed = {};
      }
    }
    voice.setFloor(allowed, widget.uid);
  }

  void _showNotice(OnlineRoom room) {
    final step = room.noticeStep ?? -1;
    // notices from before this phone opened the room are not news
    if (_noticeSeen == null || room.notice == null) {
      _noticeSeen = step;
      return;
    }
    if (step <= _noticeSeen!) return;
    _noticeSeen = step;
    final text = room.notice!;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(text)));
    });
  }

  Future<void> _openTable() async {
    _tableOpen = true;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GameScreen.online(session: session, voice: voice)));
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

  /// Back arrow: in the lobby this gives up the seat; during a game the
  /// seat is kept so the player can come back with the same code.
  Future<void> _leave() async {
    final room = session.room;
    if (room != null && room.status == 'lobby') return _leaveRoom();
    await voice.leave();
    if (mounted) Navigator.pop(context);
  }

  /// Gives up the seat for good and returns to the home screen.
  Future<void> _leaveRoom() async {
    final room = session.room;
    final midGame =
        room != null && room.inGame && session.phase != GamePhase.finished;
    if (midGame) {
      final sure = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: const Text('離開房間？'),
                content: const Text('對局正在進行。你離開後這局會中止，所有人回到房間大廳。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                          foregroundColor: Colors.redAccent),
                      child: const Text('離開房間')),
                ],
              ));
      if (sure != true) return;
    }
    setState(() => _busy = true);
    try {
      await voice.leave();
      await session.leave();
    } on GameMoveException catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
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
    final issue = onlineSetupIssue(n, room.optionalRoles, room.expansions);
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
          IconButton(
              tooltip: '發言設定',
              icon: const Icon(Icons.timer_outlined),
              onPressed: !_busy && session.isHost && !room.inGame
                  ? () async {
                      final settings =
                          await editDiscussion(context, room.discussion);
                      if (mounted && settings != null) {
                        await _run(() => session.setDiscussion(settings));
                      }
                    }
                  : null),
          VoiceControls(
              voice: voice,
              names: {for (final p in room.players) p.uid: p.name}),
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
          SizedBox(
            height: 42,
            child: OutlinedButton.icon(
              key: const ValueKey('leaveRoom'),
              style: OutlinedButton.styleFrom(
                  minimumSize: Size.zero,
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                      color: Colors.redAccent.withValues(alpha: .6))),
              onPressed: _busy ? null : _leaveRoom,
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('離開房間'),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 250,
            height: 42,
            child: ExpansionsButton(
                settings: room.expansions,
                onTap: host && !room.inGame && !_busy
                    ? () async {
                        final value =
                            await editExpansions(context, room.expansions);
                        if (mounted && value != null) {
                          await _run(() => session.setExpansions(value));
                        }
                      }
                    : null),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              room.inGame
                  ? (finished ? '對局已結束' : '對局進行中')
                  : issue ??
                      '正義 ${n - Room.evilCount(n)} 人・邪惡 ${Room.evilCount(n)} 人，其他名額自動補齊',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
        VoiceSpeakingMark(voice: voice, uid: p.uid),
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

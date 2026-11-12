import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/game_sounds.dart';
import '../game/game_model.dart';
import '../game/game_session.dart';
import '../table/table_surface.dart';
import 'notebook_model.dart';
import 'notebook_painter.dart';
import 'note_editor.dart';
import '../online/voice/voice_controller.dart';
import '../online/voice/voice_controls.dart';

class NotebookScreen extends StatefulWidget {
  const NotebookScreen(
      {super.key, required this.session, this.notebook, this.voice});
  final GameSession session;
  final GameNotebook? notebook;
  final VoiceController? voice;
  @override
  State<NotebookScreen> createState() => _NotebookScreenState();
}

class _NotebookScreenState extends State<NotebookScreen> {
  late final GameNotebook notes = widget.notebook ?? widget.session.notebook;
  GameSession get game => widget.session;
  int _page = 0, _quest = 0;
  String? _scope;

  @override
  void initState() {
    super.initState();
    _quest = min(game.history.length, 4);
    game.addListener(_changed);
    notes.addListener(_redraw);
    _bind();
  }

  void _bind() {
    if (_scope == game.notebookScope) return;
    _scope = game.notebookScope;
    _page = 0;
    _quest = min(game.history.length, 4);
    unawaited(notes.bind(_scope!));
  }

  void _changed() {
    _bind();
    _redraw();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    game.removeListener(_changed);
    notes.removeListener(_redraw);
    super.dispose();
  }

  Future<void> _edit({int? player, int? quest}) async {
    if (!notes.canEdit) return;
    GameSounds.instance.play(GameSound.page);
    final scope = _scope;
    final uid = player == null ? null : game.playerIds[player];
    final text = player == null ? notes.quest(quest!) : notes.player(uid!).text;
    final title = player == null
        ? '第 ${quest! + 1} 次遠征筆記'
        : playerLabel(player, game.players[player]);
    final edited = await showDialog<String>(
        context: context,
        builder: (_) => NoteEditor(title: title, initialText: text));
    if (!mounted || edited == null || scope != _scope) return;
    if (player == null) {
      await notes.setQuestText(quest!, edited);
    } else {
      await notes.setPlayerText(uid!, edited);
    }
  }

  Future<void> _clear() async {
    final scope = _scope;
    final clear = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('清空本局筆記？'),
                content: const Text('清除手寫筆記與善惡標記。自動保存的開局情報與投票歷史會保留。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消')),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('清空'))
                ]));
    if (mounted && clear == true && scope == _scope) await notes.clear();
  }

  TextStyle _text(double size, double s,
          {Color color = notebookInk, bool bold = false}) =>
      TextStyle(
          fontSize: size * s,
          color: color,
          height: 1.35,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal);

  @override
  Widget build(BuildContext context) => Scaffold(
      resizeToAvoidBottomInset: false,
      floatingActionButtonLocation: FloatingActionButtonLocation.endTop,
      floatingActionButton: widget.voice == null
          ? null
          : SafeArea(
              child: Material(
                  color: const Color(0xFF161C36),
                  borderRadius: BorderRadius.circular(12),
                  child: VoiceControls(
                      voice: widget.voice!,
                      compact: true,
                      names: {
                        for (var i = 0; i < game.players.length; i++)
                          game.playerIds[i]: game.players[i],
                      }))),
      body: WoodTable(
          child: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final s = min(constraints.maxWidth / 1000, constraints.maxHeight / 520)
            .clamp(.5, 2.0);
        final pages = (game.players.length / 3).ceil();
        _page = _page.clamp(0, max(0, pages - 1));
        return Padding(
            padding: EdgeInsets.fromLTRB(18 * s, 12 * s, 14 * s, 12 * s),
            child: Row(children: [
              Expanded(
                  child: RepaintBoundary(
                      child: CustomPaint(
                          painter: const NotebookPainter(),
                          child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 26 * s, vertical: 18 * s),
                              child: Row(children: [
                                Expanded(
                                    child: Padding(
                                        padding: EdgeInsets.only(right: 20 * s),
                                        child: Column(children: [
                                          SizedBox(
                                              height: 48 * s,
                                              child: Row(children: [
                                                _roundButton(
                                                    Icons.arrow_back,
                                                    '返回遊戲',
                                                    () =>
                                                        Navigator.pop(context),
                                                    s),
                                                Expanded(
                                                    child: Text('玩家筆記',
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: _text(25, s,
                                                            bold: true))),
                                                _roundButton(
                                                    Icons.badge_outlined,
                                                    '開局情報',
                                                    _opening,
                                                    s),
                                                _roundButton(
                                                    Icons.delete_outline,
                                                    '清空本局筆記',
                                                    !notes.canEdit
                                                        ? null
                                                        : _clear,
                                                    s),
                                              ])),
                                          Padding(
                                              padding: EdgeInsets.only(
                                                  bottom: 10 * s),
                                              child: Text('僅自己可見・本機保存',
                                                  style: _text(12, s,
                                                      color: notebookGold))),
                                          if (notes.error != null)
                                            Padding(
                                                padding: EdgeInsets.only(
                                                    bottom: 6 * s),
                                                child: Text(notes.error!,
                                                    maxLines: 2,
                                                    style: _text(12, s,
                                                        color: const Color(
                                                            0xFF983D2D)))),
                                          Expanded(
                                              child: notes.loading
                                                  ? const Center(
                                                      child:
                                                          CircularProgressIndicator(
                                                              color:
                                                                  notebookGold))
                                                  : Column(children: [
                                                      for (var slot = 0;
                                                          slot < 3;
                                                          slot++) ...[
                                                        if (slot > 0)
                                                          SizedBox(
                                                              height: 12 * s),
                                                        Expanded(
                                                            child: _page * 3 +
                                                                        slot <
                                                                    game.players
                                                                        .length
                                                                ? _player(
                                                                    _page * 3 +
                                                                        slot,
                                                                    s)
                                                                : const SizedBox
                                                                    .expand()),
                                                      ]
                                                    ])),
                                          SizedBox(
                                              height: 34 * s,
                                              child: Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    _roundButton(
                                                        Icons.chevron_left,
                                                        '上一頁玩家',
                                                        _page > 0
                                                            ? () {
                                                                GameSounds
                                                                    .instance
                                                                    .play(GameSound
                                                                        .page);
                                                                setState(() =>
                                                                    _page--);
                                                              }
                                                            : null,
                                                        s),
                                                    SizedBox(
                                                        width: 95 * s,
                                                        child: Text(
                                                            '${_page + 1} / $pages 頁',
                                                            textAlign: TextAlign
                                                                .center,
                                                            style:
                                                                _text(13, s))),
                                                    _roundButton(
                                                        Icons.chevron_right,
                                                        '下一頁玩家',
                                                        _page + 1 < pages
                                                            ? () {
                                                                GameSounds
                                                                    .instance
                                                                    .play(GameSound
                                                                        .page);
                                                                setState(() =>
                                                                    _page++);
                                                              }
                                                            : null,
                                                        s),
                                                  ])),
                                        ]))),
                                Expanded(
                                    child: Padding(
                                        padding: EdgeInsets.only(left: 20 * s),
                                        child: _questPage(s))),
                              ]))))),
              SizedBox(width: 8 * s),
              SizedBox(
                  width: 42 * s,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < 5; i++)
                          Padding(
                              padding: EdgeInsets.symmetric(vertical: 6 * s),
                              child: Semantics(
                                  button: true,
                                  selected: _quest == i,
                                  child: Tooltip(
                                      message: '第 ${i + 1} 次遠征',
                                      child: InkWell(
                                          key: ValueKey('notebookQuest$i'),
                                          borderRadius:
                                              BorderRadius.circular(22 * s),
                                          onTap: () {
                                            GameSounds.instance
                                                .play(GameSound.page);
                                            setState(() => _quest = i);
                                          },
                                          child: Container(
                                              width: 38 * s,
                                              height: 38 * s,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: _quest == i
                                                      ? const Color(0xFFD4B36D)
                                                      : const Color(0xFF483321),
                                                  border: Border.all(
                                                      color:
                                                          const Color(0xFFB79557)),
                                                  boxShadow: const [
                                                    BoxShadow(
                                                        color: Colors.black45,
                                                        blurRadius: 3,
                                                        offset: Offset(1, 2))
                                                  ]),
                                              child: Text('${i + 1}',
                                                  style: _text(21, s,
                                                      color: _quest == i
                                                          ? notebookInk
                                                          : const Color(0xFFF1DEAF))))))))
                      ])),
            ]));
      }))));

  Widget _roundButton(
          IconData icon, String tooltip, VoidCallback? tap, double s) =>
      IconButton(
          tooltip: tooltip,
          onPressed: tap,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(width: 36 * s, height: 34 * s),
          iconSize: 23 * s,
          color: notebookInk,
          disabledColor: notebookGold.withValues(alpha: .35),
          icon: Icon(icon));

  Widget _player(int seat, double s) {
    final uid = game.playerIds[seat], note = notes.player(game.playerIds[seat]);
    return _panel(s,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                width: 25 * s,
                height: 25 * s,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                    shape: BoxShape.circle, color: Color(0xFFCFB477)),
                child: Text('${seat + 1}', style: _text(15, s, bold: true))),
            SizedBox(width: 7 * s),
            Expanded(
                child: Text('【${game.players[seat]}】',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _text(16, s, bold: true))),
            IconButton(
                tooltip: '編輯 ${seat + 1} 號筆記',
                style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    minimumSize: Size.zero),
                onPressed: notes.canEdit ? () => _edit(player: seat) : null,
                padding: EdgeInsets.zero,
                constraints:
                    BoxConstraints.tightFor(width: 25 * s, height: 25 * s),
                icon: Icon(Icons.edit_outlined,
                    size: 16 * s, color: notebookGold)),
          ]),
          Expanded(
              child: InkWell(
                  key: ValueKey('playerNote$seat'),
                  onTap: notes.canEdit ? () => _edit(player: seat) : null,
                  child: SizedBox(
                      width: double.infinity,
                      child: Padding(
                          padding: EdgeInsets.only(top: 5 * s),
                          child: Text(
                              note.text.isEmpty ? '點一下，寫下觀察…' : note.text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _text(14, s,
                                  color: note.text.isEmpty
                                      ? notebookGold
                                      : notebookInk)))))),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            _mark(uid, seat, SuspectedSide.good, 'Good',
                note.side == SuspectedSide.good, s),
            SizedBox(width: 7 * s),
            _mark(uid, seat, SuspectedSide.evil, 'Evil',
                note.side == SuspectedSide.evil, s),
          ]),
        ]));
  }

  Widget _mark(String uid, int seat, SuspectedSide side, String label,
          bool selected, double s) =>
      Semantics(
          button: true,
          selected: selected,
          label: '${seat + 1} 號標記${side == SuspectedSide.good ? '善' : '惡'}',
          child: InkWell(
              key: ValueKey('mark${side.name}$seat'),
              onTap: notes.canEdit ? () => notes.mark(uid, side) : null,
              child: Padding(
                  padding:
                      EdgeInsets.symmetric(vertical: 3 * s, horizontal: 3 * s),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        selected
                            ? Icons.check_box_outlined
                            : Icons.check_box_outline_blank,
                        size: 17 * s,
                        color: selected
                            ? (side == SuspectedSide.good
                                ? const Color(0xFF456448)
                                : const Color(0xFF883D2D))
                            : notebookGold),
                    SizedBox(width: 3 * s),
                    Text(label, style: _text(13, s)),
                  ]))));

  Widget _questPage(double s) {
    final completed =
        _quest < game.history.length ? game.history[_quest] : null;
    final current = completed == null &&
        _quest == game.history.length &&
        ![GamePhase.assassination, GamePhase.finished].contains(game.phase);
    final team = completed?.team ?? (current ? game.team : <int>[]);
    final size = questTeamSize(game.players.length, _quest);
    final subtitle = current
        ? '隊長 ${playerLabel(game.leader, game.players[game.leader])}・派出 $size 人'
        : '派出 $size 人${game.players.length >= 7 && _quest == 3 ? '・需兩張失敗票' : ''}';
    return Column(children: [
      SizedBox(
          height: 48 * s,
          child: Center(
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
                child: Text('第 ${_quest + 1} 次遠征',
                    style: _text(25, s, bold: true))),
            _roundButton(Icons.how_to_vote_outlined, '投票歷史', _proposals, s),
          ]))),
      Padding(
          padding: EdgeInsets.only(bottom: 10 * s),
          child: Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _text(12, s, color: notebookGold))),
      Expanded(
          child: _panel(s,
              title: '遠征隊伍',
              icon: Icons.flag_outlined,
              child: _body(
                  team.isEmpty
                      ? (current ? '等待隊長提案' : '尚未有遠征隊伍')
                      : team
                          .map((seat) => playerLabel(seat, game.players[seat]))
                          .join('、'),
                  s))),
      SizedBox(height: 12 * s),
      Expanded(
          child: _panel(s,
              title: '公開結果',
              icon: Icons.shield_outlined,
              child: _body(
                  completed != null
                      ? '${completed.succeeded ? '任務成功' : '任務失敗'}\n成功 ${completed.team.length - completed.fails} 張・失敗 ${completed.fails} 張'
                      : current && game.phase == GamePhase.voteResult
                          ? '提案${game.teamApproved ? '通過' : '遭否決'}\n贊成 ${game.votes.where((v) => v).length} 票・反對 ${game.votes.where((v) => !v).length} 票'
                          : '尚未公布遠征結果',
                  s))),
      SizedBox(height: 12 * s),
      Expanded(
          child: _panel(s,
              title: '本輪筆記',
              icon: Icons.edit_note,
              child: InkWell(
                  key: const ValueKey('questNote'),
                  onTap: notes.loading ? null : () => _edit(quest: _quest),
                  child: SizedBox(
                      width: double.infinity,
                      height: double.infinity,
                      child: _body(
                          notes.quest(_quest).isEmpty
                              ? '點一下，記錄本輪推理…'
                              : notes.quest(_quest),
                          s))))),
      SizedBox(
          height: 34 * s,
          child: Center(
              child: Text('公開紀錄・不含秘密身分與未揭曉選票',
                  style: _text(11, s, color: notebookGold)))),
    ]);
  }

  Widget _body(String text, double s) => Align(
      alignment: Alignment.topLeft,
      child: Text(text,
          maxLines: 3, overflow: TextOverflow.ellipsis, style: _text(14, s)));

  void _opening() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('我的開局情報'),
              content: SingleChildScrollView(
                  child: Text(notes.opening ?? '等待本人的角色牌資料…')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('關閉'))
              ]));

  void _proposals() {
    final records = (game.proposalHistory.length >= notes.proposals.length
            ? game.proposalHistory
            : notes.proposals)
        .where((p) => p.quest == _quest + 1)
        .toList();
    String player(int seat) => playerLabel(seat, game.players[seat]);
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text('第 ${_quest + 1} 次遠征・投票歷史'),
                content: SizedBox(
                    width: 550,
                    child: records.isEmpty
                        ? const Text('全員投票完成後，提案與每人的票型才會出現在這裡。')
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: records.length,
                            separatorBuilder: (_, index) =>
                                const Divider(height: 24),
                            itemBuilder: (_, index) {
                              final p = records[index];
                              return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '第 ${p.attempt} 次提案・${p.approved ? '通過' : '否決'}',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: p.approved
                                                ? Colors.green
                                                : Colors.redAccent)),
                                    Text('隊長：${player(p.leader)}'),
                                    Text('隊伍：${p.team.map(player).join('、')}'),
                                    const SizedBox(height: 8),
                                    for (var i = 0; i < p.votes.length; i++)
                                      Text(
                                          '${player(i)}：${p.votes[i] ? '贊成' : '反對'}'),
                                  ]);
                            })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('關閉'))
                ]));
  }

  Widget _panel(double s,
          {String? title, IconData? icon, required Widget child}) =>
      Container(
          padding: EdgeInsets.all(10 * s),
          decoration: BoxDecoration(
              color: const Color(0xFFFFF4CF).withValues(alpha: .22),
              border: Border.all(
                  color: notebookGold.withValues(alpha: .55), width: .9 * s),
              borderRadius: BorderRadius.circular(5 * s)),
          child: title == null
              ? child
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(icon, color: notebookGold, size: 17 * s),
                    SizedBox(width: 6 * s),
                    Text(title, style: _text(15, s, bold: true))
                  ]),
                  SizedBox(height: 7 * s),
                  Expanded(child: child),
                ]));
}

import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../persona/bot_persona.dart';
import '../review_screen.dart';
import 'match_archive.dart';
import 'match_repository.dart';
import 'social_memory.dart';

/// Past solo games on this device, and the computer players who remember
/// them. Opening a game shows its full review again.
class MatchHistoryScreen extends StatefulWidget {
  const MatchHistoryScreen({super.key, this.repository});
  final MatchRepository? repository;
  @override
  State<MatchHistoryScreen> createState() => _MatchHistoryScreenState();
}

class _MatchHistoryScreenState extends State<MatchHistoryScreen> {
  late final MatchRepository _repository =
      widget.repository ?? MatchRepository.shared;
  List<MatchSummary>? _matches;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final matches = await _repository.summaries();
    if (mounted) setState(() => _matches = matches);
  }

  Future<void> _open(MatchSummary summary) async {
    final match = await _repository.load(summary.id);
    if (!mounted) return;
    if (match == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('這局的紀錄讀不出來')));
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReviewScreen(review: match.review)));
  }

  Future<void> _clear() async {
    final sure = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('清除所有紀錄？'),
              content: const Text('對局紀錄會全部刪除，電腦玩家也會忘記以前跟你玩過的每一局。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消')),
                TextButton(
                    key: const ValueKey('confirmClearHistory'),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('全部清除')),
              ],
            ));
    if (sure != true) return;
    await _repository.clear();
    await _load();
  }

  static String _date(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.month}/${t.day} ${two(t.hour)}:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final wins = matches?.where((m) => m.won).length ?? 0;
    return Scaffold(
        body: FantasyBackground(
            child: SafeArea(
                child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
              color: AvalonTheme.gold),
          const Text('對局紀錄',
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AvalonTheme.gold)),
          const SizedBox(width: 12),
          if (matches != null && matches.isNotEmpty)
            Text('${matches.length} 局・你贏 $wins 局',
                style: const TextStyle(fontSize: 13, color: AvalonTheme.muted)),
          const Spacer(),
          if (matches != null && matches.isNotEmpty)
            TextButton.icon(
                key: const ValueKey('clearHistory'),
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('全部清除')),
        ]),
        const SizedBox(height: 6),
        Expanded(
            child: matches == null
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        Expanded(
                            flex: 6,
                            child: GoldPanel(
                                padding: const EdgeInsets.all(10),
                                child: matches.isEmpty
                                    ? const Center(
                                        child: Text('還沒有紀錄。跟電腦打完一局就會出現在這裡。',
                                            style: TextStyle(
                                                color: AvalonTheme.muted)))
                                    : ListView.separated(
                                        itemCount: matches.length,
                                        separatorBuilder: (_, __) =>
                                            const Divider(height: 1),
                                        itemBuilder: (_, i) =>
                                            _row(matches[i])))),
                        const SizedBox(width: 10),
                        Expanded(
                            flex: 5,
                            child: GoldPanel(
                                padding: const EdgeInsets.all(10),
                                child: ListView(children: [
                                  const SectionLabel('電腦玩家記得的事'),
                                  const SizedBox(height: 6),
                                  for (final p in BotPersona.cast)
                                    _persona(p, matches),
                                ]))),
                      ])),
      ]),
    ))));
  }

  Widget _row(MatchSummary m) => ListTile(
        key: ValueKey('match_${m.id}'),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: Icon(m.won ? Icons.emoji_events : Icons.close,
            color: m.won ? AvalonTheme.gold : AvalonTheme.muted),
        title: Text('${m.won ? '勝' : '敗'}・${m.myRole.label}・${m.players} 人',
            style: const TextStyle(fontSize: 14)),
        subtitle: Text(
            '${_date(m.endedAt)}・${m.winner}獲勝${m.difficulty.isEmpty ? '' : '・${m.difficulty}'}',
            style: const TextStyle(fontSize: 11.5, color: AvalonTheme.muted)),
        trailing: IconButton(
            tooltip: '刪除這局',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: () async {
              await _repository.delete(m.id);
              await _load();
            }),
        onTap: () => _open(m),
      );

  Widget _persona(BotPersona p, List<MatchSummary> matches) {
    final memory = BotMemory.of(p.id, matches, 0);
    final last = memory?.entries.first;
    final personal = last?.kinds.where((k) => k.personal).toList() ?? const [];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${p.name}　${p.bio}',
            style: const TextStyle(fontSize: 13, color: Color(0xFFE8E2D2))),
        Text(memorySummary(memory),
            style: const TextStyle(fontSize: 11.5, color: AvalonTheme.muted)),
        if (last != null && personal.isNotEmpty)
          Text(
              '「${memoryLines(personal.first, last.ago == 0 ? '上一局' : '之前', '你').first.replaceFirst(RegExp('^你，'), '')}」',
              style: const TextStyle(fontSize: 11.5, color: AvalonTheme.gold)),
      ]),
    );
  }
}

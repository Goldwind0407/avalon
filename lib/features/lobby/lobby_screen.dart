import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'room_model.dart';
import '../game/game_screen.dart';

class _PlayerNameDialog extends StatefulWidget {
  const _PlayerNameDialog();
  @override
  State<_PlayerNameDialog> createState() => _PlayerNameDialogState();
}

class _PlayerNameDialogState extends State<_PlayerNameDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    final name = controller.text.trim();
    if (name.isNotEmpty && name.length <= 16) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('新增同機玩家'),
        content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 16,
            decoration: const InputDecoration(labelText: '玩家暱稱'),
            onSubmitted: (_) => submit()),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: submit, child: const Text('加入')),
        ],
      );
}

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key, required this.room, required this.repository});
  final Room room;
  final LocalRoomRepository repository;
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  Room get room => widget.room;
  Player get self => room.players.firstWhere((p) => p.id == 'local');
  static const roleNames = ['梅林', '派西維爾', '莫甘娜', '莫德雷德', '奧伯倫', '刺客'];
  static const roleDescriptions = {
    '梅林': '正義 · 能看見多數邪惡玩家',
    '派西維爾': '正義 · 能看見梅林與莫甘娜候選人',
    '莫甘娜': '邪惡 · 在派西維爾眼中偽裝為梅林',
    '莫德雷德': '邪惡 · 不會被梅林看見',
    '奧伯倫': '邪惡 · 不與其他邪惡玩家互認',
    '刺客': '邪惡 · 正義完成三次任務後刺殺梅林',
  };

  void notify(String message) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));

  void toggleReady() => setState(() => self.isReady = !self.isReady);

  void toggleRole(String role, bool value) {
    if (role == '梅林' || role == '刺客') return;
    setState(() {
      if (value) {
        room.specialRoles.add(role);
      } else {
        room.specialRoles.remove(role);
      }
      self.isReady = false;
    });
  }

  String? get roleIssue => room.roleIssue;

  Future<void> addPlayer() async {
    if (room.players.length >= 10) return;
    final name = await showDialog<String>(
        context: context, builder: (context) => const _PlayerNameDialog());
    if (!mounted || name == null) return;
    setState(() {
      widget.repository.addDemoPlayer(room, name: name);
      self.isReady = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('私人議會'), actions: [
          IconButton(
              tooltip: '房間資訊',
              onPressed: () => notify('同機傳遞模式：大家共用手機遊玩，目前尚未支援跨裝置連線'),
              icon: const Icon(Icons.info_outline)),
        ]),
        body: FantasyBackground(
            child: SafeArea(
                child: Center(
                    child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
              children: [
                GoldPanel(
                    child: Column(children: [
                  const SectionLabel('PRIVATE CHAMBER · 私人房間'),
                  const SizedBox(height: 8),
                  Text(room.code,
                      style: const TextStyle(
                          color: AvalonTheme.gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 41,
                          letterSpacing: 10)),
                  const SizedBox(height: 5),
                  const Text('同機傳遞模式 · 房號僅供本機識別',
                      style: TextStyle(color: AvalonTheme.muted, fontSize: 12)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: room.code));
                        if (context.mounted) notify('已複製，可從首頁返回此本機房間');
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text('複製房號')),
                ])),
                const SizedBox(height: 20),
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('KNIGHTS · 議會成員'),
                      Text('${room.players.length} / 10',
                          style: const TextStyle(color: AvalonTheme.gold)),
                    ]),
                const SizedBox(height: 10),
                ...room.players.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                          color: AvalonTheme.surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: p.id == 'local'
                                  ? AvalonTheme.gold.withValues(alpha: .6)
                                  : AvalonTheme.raised)),
                      child: Row(children: [
                        CircleAvatar(
                            backgroundColor: AvalonTheme.raised,
                            child: Icon(
                                p.isHost
                                    ? Icons.workspace_premium
                                    : Icons.person_outline,
                                color: AvalonTheme.gold)),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(p.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600))),
                        if (p.isHost)
                          const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Text('房主',
                                  style: TextStyle(
                                      color: AvalonTheme.gold, fontSize: 12))),
                        Text(p.isReady ? '已準備' : '未準備',
                            style: TextStyle(
                                color: p.isReady
                                    ? AvalonTheme.green
                                    : AvalonTheme.muted,
                                fontSize: 12)),
                      ]),
                    ))),
                const SizedBox(height: 10),
                GoldPanel(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      const SectionLabel('ROLE SETTINGS · 角色配置'),
                      const SizedBox(height: 7),
                      const Text('梅林與刺客為必要角色；其他角色可依玩家人數調整。',
                          style: TextStyle(
                              color: AvalonTheme.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      ...roleNames.map((r) => SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title:
                                Text(r, style: const TextStyle(fontSize: 15)),
                            subtitle: Text(roleDescriptions[r]!,
                                style: const TextStyle(
                                    color: AvalonTheme.muted, fontSize: 11)),
                            value: room.specialRoles.contains(r),
                            onChanged: (r == '梅林' || r == '刺客')
                                ? null
                                : (v) => toggleRole(r, v),
                            activeTrackColor: AvalonTheme.violet,
                          )),
                      if (roleIssue != null)
                        Text(roleIssue!,
                            style: const TextStyle(color: Colors.orangeAccent)),
                    ])),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                    onPressed: room.players.length < 10 ? addPlayer : null,
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('新增同機玩家')),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                    onPressed: room.players.length > 1
                        ? () => setState(() {
                              widget.repository.removeDemoPlayer(room);
                              self.isReady = false;
                            })
                        : null,
                    icon: const Icon(Icons.person_remove_alt_1),
                    label: const Text('移除最後一位玩家')),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                    onPressed: toggleReady,
                    icon: Icon(self.isReady
                        ? Icons.check_circle
                        : Icons.hourglass_bottom),
                    label: Text(self.isReady ? '取消準備' : '我已準備')),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                    onPressed: room.canStart
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => GameScreen(room: room)))
                        : null,
                    icon: const Icon(Icons.shield),
                    label: const Text('開始對局')),
                const SizedBox(height: 16),
                const Text(
                    '新增 5～10 位在場玩家後，由房主確認準備。開始後依畫面提示傳遞手機，每人秘密查看身分並操作。離開對局或關閉 App 後不保留進度。',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: AvalonTheme.muted)),
              ]),
        )))),
      );
}

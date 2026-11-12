import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'expansion_model.dart';

Future<ExpansionSettings?> editExpansions(
        BuildContext context, ExpansionSettings initial, {int? players}) =>
    showDialog<ExpansionSettings>(
        context: context, builder: (_) => _ExpansionDialog(initial, players));

class _ExpansionDialog extends StatefulWidget {
  const _ExpansionDialog(this.initial, this.players);
  final ExpansionSettings initial;
  final int? players;
  @override
  State<_ExpansionDialog> createState() => _ExpansionDialogState();
}

class _ExpansionDialogState extends State<_ExpansionDialog> {
  late var value = widget.initial;
  bool get lancelotAllowed =>
      widget.players == null || widget.players! >= lancelotMinPlayers;
  void help(String title, String text) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(child: Text(text)),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('了解'))
              ]));

  Widget card(String title, IconData icon, Widget control, String summary,
          String details) =>
      Expanded(
          child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AvalonTheme.raised,
                  border:
                      Border.all(color: AvalonTheme.gold.withValues(alpha: .3)),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                Row(children: [
                  Icon(icon, color: AvalonTheme.gold, size: 20),
                  const SizedBox(width: 5),
                  Expanded(
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(title,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold))))
                ]),
                const SizedBox(height: 4),
                control,
                Expanded(
                    child: Align(
                        alignment: Alignment.topLeft,
                        child: Text(summary,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: AvalonTheme.muted)))),
                TextButton(
                    style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 8)),
                    onPressed: () => help(title, details),
                    child: const Text('規則說明')),
              ])));

  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 360),
          child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                const SizedBox(
                    height: 30,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('擴充規則',
                            style: TextStyle(
                                fontSize: 20, color: AvalonTheme.gold)))),
                const SizedBox(height: 8),
                Expanded(
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                      card(
                          '湖中女神',
                          Icons.water_drop_outlined,
                          Switch(
                              key: const ValueKey('expansionLady'),
                              value: value.lady,
                              onChanged: (v) => setState(
                                  () => value = value.copyWith(lady: v))),
                          '第 2～4 次任務後，查驗一名玩家的陣營。',
                          '第 2、3、4 次任務結束後，持有者查驗一名玩家的陣營，再把湖中女神交給對方。'
                              '持有過的人不能再被查驗。建議 7 人以上。'),
                      const SizedBox(width: 10),
                      card(
                          '蘭斯洛特',
                          Icons.swap_horiz,
                          DropdownButton<int>(
                              key: const ValueKey('expansionLancelot'),
                              value: value.lancelot,
                              isExpanded: true,
                              items: [
                                for (var i = 0; i < 3; i++)
                                  DropdownMenuItem(
                                      value: i,
                                      enabled: i == 0 || lancelotAllowed,
                                      child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                              [
                                                '不使用',
                                                '變體一・每輪翻牌',
                                                '變體二・開局公開'
                                              ][i],
                                              style: TextStyle(
                                                  color:
                                                      i == 0 || lancelotAllowed
                                                          ? null
                                                          : AvalonTheme.muted,
                                                  fontSize: 13))))
                              ],
                              onChanged: (v) {
                                if (v != null && (v == 0 || lancelotAllowed)) {
                                  setState(() =>
                                      value = value.copyWith(lancelot: v));
                                }
                              }),
                          !lancelotAllowed
                              ? '需要 7 人以上（目前 ${widget.players} 人）。'
                              : value.lancelot > 0
                                  ? '自動加入正義、邪惡蘭斯洛特各一位，角色會鎖定勾選。'
                                  : '需要 7 人以上；依轉換牌交換陣營。',
                          '正義與邪惡蘭斯洛特各占一個陣營名額，兩人互不認識。其他邪惡玩家知道誰是邪惡蘭斯洛特，'
                              '但他看不到他們；梅林分不出他是蘭斯洛特。\n\n變體一：7 張牌（5 張不變、2 張轉換）洗勻，第 3 次任務起每輪翻一張。'
                              '\n\n變體二：開局公開 5 張轉換牌；執行任務時，當前正義方只能出成功，邪惡方必須出失敗。'),
                      const SizedBox(width: 10),
                      card(
                          '王者之劍',
                          Icons.gavel_outlined,
                          Switch(
                              key: const ValueKey('expansionExcalibur'),
                              value: value.excalibur,
                              onChanged: (v) => setState(
                                  () => value = value.copyWith(excalibur: v))),
                          '隊長將劍交給隊員，持劍者可翻轉一張任務牌。',
                          '隊長提案時，把劍交給隊長以外的一名隊員。任務牌收走前，持劍者可以翻轉另一名隊員的任務牌，'
                              '並私下看到原本的票型；公開時會將所有任務牌洗勻。'),
                    ])),
                const SizedBox(height: 8),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('取消')),
                  const SizedBox(width: 8),
                  TextButton(
                      key: const ValueKey('expansionSave'),
                      onPressed: () => Navigator.pop(context, value),
                      child: const Text('儲存')),
                ]),
              ]))));
}

class ExpansionsButton extends StatelessWidget {
  const ExpansionsButton(
      {super.key, required this.settings, required this.onTap});
  final ExpansionSettings settings;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
      color: settings.any
          ? AvalonTheme.violet.withValues(alpha: .3)
          : AvalonTheme.raised,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
          key: const ValueKey('expansions'),
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                const Icon(Icons.extension_outlined,
                    size: 18, color: AvalonTheme.gold),
                const SizedBox(width: 8),
                Expanded(
                    child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      const Text('擴充規則',
                          style: TextStyle(fontSize: 13, color: Colors.white)),
                      Text(
                          settings.any
                              ? settings.summary
                              : '未使用・湖中女神／蘭斯洛特／王者之劍',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: settings.any
                                  ? AvalonTheme.gold
                                  : AvalonTheme.muted)),
                    ])),
                if (onTap != null)
                  const Icon(Icons.chevron_right,
                      size: 18, color: AvalonTheme.muted),
              ]))));
}

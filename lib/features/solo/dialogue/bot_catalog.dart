import 'dart:convert';
import '../../game/game_model.dart';
import 'bot_contract.dart';
import 'generated/bot_dialogue_data.dart';

class BotSpeechRule {
  BotSpeechRule._(
      {required this.id,
      required this.role,
      required this.phase,
      required this.intent,
      required this.policy,
      required this.priority,
      required this.scenario,
      required List<String> requires,
      required List<String> templates})
      : requires = List.unmodifiable(requires),
        templates = List.unmodifiable(templates);
  factory BotSpeechRule.fromMap(Map<String, dynamic> map) {
    final id = map['id'];
    final priority = map['priority'];
    if (id is! String ||
        !RegExp(r'^[A-Z]+\d+$').hasMatch(id) ||
        priority is! int ||
        priority < 0 ||
        priority > 100 ||
        map['scenario'] is! String ||
        ['role', 'phase', 'intent', 'policy']
            .any((key) => map[key] is! String)) {
      throw const FormatException('Invalid speech rule');
    }
    List<String> strings(String key) {
      final values = map[key];
      if (values is! List || values.any((s) => s is! String || s.isEmpty)) {
        throw FormatException('Invalid $key for $id');
      }
      return values.cast<String>();
    }

    final templates = strings('templates');
    if (templates.isEmpty) throw FormatException('No templates for $id');
    const placeholders = {
      'target',
      'quest',
      'attempt',
      'fails',
      'otherMembers',
      'reusedMembers',
      'claimant',
      'claimedAlignment',
      'newMember',
      'oldMember',
      'defender'
    };
    for (final template in templates) {
      final remainder =
          template.replaceAllMapped(RegExp(r'\{\{([A-Za-z]+)\}\}'), (match) {
        if (!placeholders.contains(match[1])) {
          throw FormatException('Unknown placeholder for $id');
        }
        return '';
      });
      if (remainder.contains('{') || remainder.contains('}')) {
        throw FormatException('Malformed placeholder for $id');
      }
    }
    // Only exact canonical enum names are accepted after draft normalization.
    try {
      return BotSpeechRule._(
          id: id,
          priority: priority,
          role: BotDialogueRole.values.byName(map['role'] as String),
          phase: GamePhase.values.byName(map['phase'] as String),
          intent: BotSpeechIntent.values.byName(map['intent'] as String),
          policy: BotClaimPolicy.values.byName(map['policy'] as String),
          scenario: map['scenario'] as String,
          requires: strings('requires'),
          templates: templates);
    } on ArgumentError {
      throw FormatException('Unknown role, intent, phase or policy for $id');
    }
  }
  final String id, scenario;
  final BotDialogueRole role;
  final GamePhase phase;
  final BotSpeechIntent intent;
  final BotClaimPolicy policy;
  final int priority;
  final List<String> requires, templates;
}

class BotDialogueCatalog {
  BotDialogueCatalog._(List<BotSpeechRule> rules)
      : rules = List.unmodifiable(rules);
  static final bundled = BotDialogueCatalog.parse(botDialogueData);
  factory BotDialogueCatalog.parse(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic> ||
        json['schemaVersion'] != 1 ||
        json['rules'] is! List) {
      throw const FormatException('Unsupported dialogue schema');
    }
    final rules = <BotSpeechRule>[];
    for (final value in json['rules'] as List) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Invalid dialogue rule');
      }
      rules.add(BotSpeechRule.fromMap(value));
    }
    if (rules.map((r) => r.id).toSet().length != rules.length) {
      throw const FormatException('Duplicate dialogue rule');
    }
    return BotDialogueCatalog._(rules);
  }
  final List<BotSpeechRule> rules;
}

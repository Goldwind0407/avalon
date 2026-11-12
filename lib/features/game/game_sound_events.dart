import '../../core/game_sounds.dart';
import 'game_model.dart';

/// Results sound only when animations reveal them, never on secret state.
GameSound? phaseSound(GamePhase phase) => switch (phase) {
      GamePhase.team || GamePhase.vote => GameSound.turn,
      GamePhase.quest => GameSound.questStart,
      GamePhase.lady || GamePhase.excalibur => GameSound.magic,
      GamePhase.ladyResult || GamePhase.excaliburResult => GameSound.flip,
      GamePhase.assassination => GameSound.assassin,
      _ => null,
    };

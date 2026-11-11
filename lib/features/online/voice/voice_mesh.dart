import 'dart:async';
import 'dart:math';
import 'voice_signaling.dart';

enum PeerState { connecting, connected, failed, closed }

/// Native WebRTC boundary, replaced by fakes in handshake tests.
abstract class VoicePeer {
  void Function(Map<String, dynamic> candidate)? onCandidate;
  void Function(PeerState state)? onState;
  Future<Map<String, dynamic>> createOffer();
  Future<Map<String, dynamic>> acceptOffer(Map<String, dynamic> offer);
  Future<void> acceptAnswer(Map<String, dynamic> answer);
  Future<void> addCandidate(Map<String, dynamic> candidate);
  Future<double> remoteLevel();
  void setPlaybackEnabled(bool enabled) {}
  Future<void> close();
}

typedef PeerFactory = Future<VoicePeer> Function();

class _Link {
  _Link(this.uid, this.session, this.attempt, this.peer);
  final String uid, session;
  final int attempt;
  final VoicePeer peer;
  PeerState state = PeerState.connecting;
  bool remoteSet = false, descriptionSent = false, closed = false;
  final incoming = <Map<String, dynamic>>[];
  final outgoing = <Map<String, dynamic>>[];
  Timer? timeout, retry;
}

/// Full mesh: one audio connection per pair. The smaller UID offers.
/// Sessions AND attempts fence off stale answers/candidates. Upload work grows
/// with room size; validate the 10-player case on actual phones.
class VoiceMesh {
  VoiceMesh({
    required this.uid,
    required this.signaling,
    required this.createPeer,
    String? session,
    this.retryDelay = const Duration(seconds: 2),
    this.handshakeTimeout = const Duration(seconds: 20),
    this.heartbeatInterval = const Duration(seconds: 30),
    this.maxAttempts = 4,
  }) : session = session ?? newSession();

  final String uid, session;
  final VoiceSignaling signaling;
  final PeerFactory createPeer;
  final Duration retryDelay, handshakeTimeout, heartbeatInterval;
  final int maxAttempts;
  final _links = <String, _Link>{};
  final _present = <String, String>{};
  final _attempts = <String, int>{};
  final _pendingSignals = <String, VoiceSignal>{};
  final _seen = <String>{};
  final _earlyCandidates = <String, List<Map<String, dynamic>>>{};
  final _queues = <String, Future<void>>{};
  final _subs = <StreamSubscription<Object?>>[];
  final _changes = StreamController<void>.broadcast();
  Timer? _heartbeat;
  bool _stopped = false, _refreshing = false;
  Future<void>? _stopping;

  static String newSession() {
    final random = Random.secure();
    return List.generate(24, (_) => random.nextInt(36).toRadixString(36))
        .join();
  }

  Stream<void> get changes => _changes.stream;
  Set<String> get participants => _present.keys.toSet();
  Set<String> get connected => {
        for (final link in _links.values)
          if (link.state == PeerState.connected) link.uid
      };
  Map<String, VoicePeer> get peers => {
        for (final link in _links.values)
          if (link.state == PeerState.connected) link.uid: link.peer
      };
  Map<String, VoicePeer> get allPeers =>
      {for (final link in _links.values) link.uid: link.peer};

  void _changed() {
    if (!_stopped) _changes.add(null);
  }

  void _error(Object error, StackTrace stack) {
    if (!_stopped) _changes.addError(error, stack);
  }

  Future<void> start() async {
    await signaling.announce(VoicePresence(uid, session));
    if (_stopped) {
      await signaling.withdraw(VoicePresence(uid, session));
      return;
    }
    // Offers persist until consumed, so announcing before subscribing is safe.
    _subs
      ..add(signaling.presence().listen(_onPresence, onError: _error))
      ..add(signaling.inbox(uid).listen(_onInbox, onError: _error));
    _heartbeat = Timer.periodic(heartbeatInterval, (_) async {
      if (_stopped || _refreshing) return;
      _refreshing = true;
      try {
        await signaling.announce(VoicePresence(uid, session));
        if (_stopped) await signaling.withdraw(VoicePresence(uid, session));
      } catch (error, stack) {
        _error(error, stack);
      } finally {
        _refreshing = false;
      }
    });
  }

  Future<void> stop() => _stopping ??= _stop();

  Future<void> _stop() async {
    _stopped = true;
    _heartbeat?.cancel();
    final cancelled = [for (final sub in _subs) sub.cancel()];
    // Release audio before waiting on network operations or subscriptions.
    await Future.wait([
      for (final link in [..._links.values]) _close(link)
    ]);
    await Future.wait(cancelled);
    try {
      await signaling.withdraw(VoicePresence(uid, session));
    } finally {
      await _changes.close();
    }
  }

  void _serial(String peer, Future<void> Function() work) {
    _queues[peer] = (_queues[peer] ?? Future<void>.value()).then((_) async {
      if (_stopped) return;
      try {
        await work();
      } catch (_) {
        final link = _links[peer];
        if (link != null) {
          _stateChanged(link, PeerState.failed);
        } else {
          _error(StateError('Unable to create an audio connection'),
              StackTrace.current);
        }
      }
    });
  }

  void _onPresence(List<VoicePresence> people) {
    if (_stopped) return;
    final previous = Map<String, String>.of(_present);
    _present
      ..clear()
      ..addEntries([
        for (final p in people)
          if (p.uid != uid) MapEntry(p.uid, p.session)
      ]);
    for (final entry in previous.entries) {
      if (_present[entry.key] != entry.value) {
        _attempts.remove(entry.key);
        final link = _links[entry.key];
        if (link != null) _serial(entry.key, () => _close(link));
      }
    }
    for (final entry in _present.entries) {
      if (uid.compareTo(entry.key) < 0 &&
          _links[entry.key]?.session != entry.value) {
        _serial(entry.key, () => _offer(entry.key, entry.value));
      }
    }
    _drainInbox();
    _changed();
  }

  void _onInbox(List<VoiceSignal> signals) {
    if (_stopped) return;
    for (final signal in signals) {
      if (_seen.add(signal.id)) _pendingSignals[signal.id] = signal;
    }
    _drainInbox();
  }

  void _drainInbox() {
    final ready = _pendingSignals.values
        .where((s) => s.toSession != session || _present.containsKey(s.from))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    for (final signal in ready) {
      _pendingSignals.remove(signal.id);
      _serial(signal.from, () async {
        if (signal.toSession == session &&
            _present[signal.from] == signal.fromSession) {
          await _handle(signal);
        }
        await signaling.consume(signal.id);
      });
    }
  }

  Future<_Link?> _open(String peer, String theirs, int attempt) async {
    final old = _links[peer];
    if (old != null) await _close(old);
    final native = await createPeer();
    if (_stopped || _present[peer] != theirs) {
      await native.close();
      return null;
    }
    final link = _Link(peer, theirs, attempt, native);
    _links[peer] = link;
    _changed();
    link.incoming
        .addAll(_earlyCandidates.remove('$peer/$theirs/$attempt') ?? []);
    native.onCandidate = (candidate) {
      if (link.closed || _stopped) return;
      if (!link.descriptionSent) {
        link.outgoing.add(candidate);
      } else {
        _serial(peer, () => _send(link, 'candidate', candidate));
      }
    };
    native.onState = (state) => _stateChanged(link, state);
    link.timeout = Timer(handshakeTimeout, () {
      if (link.state != PeerState.connected) {
        _stateChanged(link, PeerState.failed);
      }
    });
    return link;
  }

  Future<void> _offer(String peer, String theirs) async {
    if (_present[peer] != theirs || _links[peer]?.session == theirs) return;
    final attempt = (_attempts[peer] ?? 0) + 1;
    _attempts[peer] = attempt;
    final link = await _open(peer, theirs, attempt);
    if (link != null) {
      await _description(link, 'offer', await link.peer.createOffer());
    }
  }

  Future<void> _handle(VoiceSignal signal) async {
    var link = _links[signal.from];
    switch (signal.kind) {
      case 'offer':
        if (signal.from.compareTo(uid) >= 0) return;
        if (signal.attempt <= (_attempts[signal.from] ?? 0)) return;
        _attempts[signal.from] = signal.attempt;
        link = await _open(signal.from, signal.fromSession, signal.attempt);
        if (link == null) return;
        final answer = await link.peer.acceptOffer(signal.data);
        await _remoteReady(link);
        await _description(link, 'answer', answer);
      case 'answer':
        if (!_matches(link, signal) || link!.remoteSet) return;
        await link.peer.acceptAnswer(signal.data);
        await _remoteReady(link);
      case 'candidate':
        if (!_matches(link, signal)) {
          if (signal.from.compareTo(uid) < 0 &&
              signal.attempt > (_attempts[signal.from] ?? 0) &&
              _earlyCandidates.length < 32) {
            final pending = _earlyCandidates.putIfAbsent(
                '${signal.from}/${signal.fromSession}/${signal.attempt}',
                () => []);
            if (pending.length < 64) pending.add(signal.data);
          }
          return;
        }
        if (link!.remoteSet) {
          await link.peer.addCandidate(signal.data);
        } else if (link.incoming.length < 64) {
          link.incoming.add(signal.data);
        }
    }
  }

  bool _matches(_Link? link, VoiceSignal signal) =>
      link != null &&
      !link.closed &&
      link.session == signal.fromSession &&
      link.attempt == signal.attempt;

  Future<void> _remoteReady(_Link link) async {
    link.remoteSet = true;
    for (final candidate in link.incoming) {
      await link.peer.addCandidate(candidate);
    }
    link.incoming.clear();
  }

  Future<void> _description(
      _Link link, String kind, Map<String, dynamic> data) async {
    await _send(link, kind, data);
    link.descriptionSent = true;
    for (final candidate in link.outgoing) {
      await _send(link, 'candidate', candidate);
    }
    link.outgoing.clear();
  }

  Future<void> _send(_Link link, String kind, Map<String, dynamic> data) {
    if (_stopped || link.closed) return Future<void>.value();
    return signaling.send(VoiceSignal(
        from: uid,
        fromSession: session,
        to: link.uid,
        toSession: link.session,
        attempt: link.attempt,
        kind: kind,
        data: data));
  }

  void _stateChanged(_Link link, PeerState state) {
    if (_stopped || link.closed || _links[link.uid] != link) return;
    link.state = state;
    if (state == PeerState.connected) {
      link.timeout?.cancel();
      link.retry?.cancel();
    }
    _changed();
    if ((state == PeerState.failed || state == PeerState.closed) &&
        uid.compareTo(link.uid) < 0 &&
        link.attempt < maxAttempts &&
        !(link.retry?.isActive ?? false)) {
      link.retry = Timer(retryDelay * (1 << (link.attempt - 1)), () {
        _serial(link.uid, () async {
          if (_links[link.uid] != link || link.state == PeerState.connected) {
            return;
          }
          await _close(link);
          final theirs = _present[link.uid];
          if (theirs != null) await _offer(link.uid, theirs);
        });
      });
    }
  }

  Future<void> _close(_Link link) async {
    if (link.closed) return;
    link.closed = true;
    link.timeout?.cancel();
    link.retry?.cancel();
    if (_links[link.uid] == link) _links.remove(link.uid);
    try {
      await link.peer.close();
    } catch (_) {/* Already gone. */}
    _changed();
  }
}

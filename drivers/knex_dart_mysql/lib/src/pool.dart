import 'dart:async';
import 'dart:collection';

/// Wraps a pooled connection with its last-idle timestamp.
class PoolResource<C> {
  final C conn;
  DateTime idleSince;
  PoolResource(this.conn) : idleSince = DateTime.now();
}

/// A pending acquire request — resolved when a connection becomes available.
class PoolWaiter<C> {
  final _c = Completer<C>();
  Future<C> get future => _c.future;
  void complete(C value) => _c.complete(value);
  void completeError(Object e) => _c.completeError(e);
}

/// A tarn.js-inspired generic connection pool.
///
/// Features over a simple pool:
/// - Per-connection idle timestamp; stale connections reaped by a timer.
/// - Proactive minimum-connection maintenance via [_ensureMin].
/// - Explicit [_free] / [_used] lists — no implicit counter arithmetic.
/// - Optional [validate] callback health-checks connections before reuse.
class TarnPool<C> {
  final Future<C> Function() create;
  final Future<void> Function(C) destroy;
  final bool Function(C)? validate;

  final int min;
  final int max;
  final Duration acquireTimeout;
  final Duration idleTimeout;
  final Duration reapInterval;

  final List<PoolResource<C>> _free = [];
  final List<PoolResource<C>> _used = [];
  final Queue<PoolWaiter<C>> _pendingAcquires = Queue();

  int _creating = 0;
  bool _destroyed = false;
  Timer? _reapTimer;

  TarnPool({
    required this.create,
    required this.destroy,
    this.validate,
    required this.min,
    required this.max,
    required this.acquireTimeout,
    required this.idleTimeout,
    required this.reapInterval,
  }) {
    _ensureMin();
  }

  /// Total connections: free + in-use + being asynchronously created.
  int get _total => _free.length + _used.length + _creating;

  // ─── Public API ──────────────────────────────────────────────────────────────

  Future<C> acquire() async {
    if (_destroyed) throw StateError('Connection pool is closed');

    // 1. Try idle connections (validate if configured).
    final v = validate;
    while (_free.isNotEmpty) {
      final resource = _free.removeLast();
      if (v == null || v(resource.conn)) {
        _used.add(resource);
        _startReaping();
        return resource.conn;
      }
      destroy(resource.conn).ignore();
    }

    // 2. Create a new connection if under capacity.
    if (_total < max) {
      return _createAndAcquire();
    }

    // 3. At capacity — queue the waiter with a timeout.
    final waiter = PoolWaiter<C>();
    _pendingAcquires.add(waiter);
    return waiter.future.timeout(
      acquireTimeout,
      onTimeout: () {
        _pendingAcquires.remove(waiter);
        throw TimeoutException(
          'Could not acquire connection within $acquireTimeout',
        );
      },
    );
  }

  /// Return a healthy connection to the pool.
  void release(C conn) {
    if (_destroyed) {
      destroy(conn).ignore();
      return;
    }
    final idx = _used.indexWhere((r) => r.conn == conn);
    if (idx == -1) return; // unknown — ignore
    final resource = _used.removeAt(idx);

    // Validate before recycling.
    final v = validate;
    if (v != null && !v(conn)) {
      destroy(conn).ignore();
      _fillPendingOrEnsureMin();
      return;
    }

    // Hand directly to a waiting acquirer if one is queued.
    if (_pendingAcquires.isNotEmpty) {
      _used.add(resource);
      _pendingAcquires.removeFirst().complete(conn);
      return;
    }

    resource.idleSince = DateTime.now();
    _free.add(resource);
  }

  /// Permanently remove a broken connection from the pool.
  void discard(C conn) {
    final idx = _used.indexWhere((r) => r.conn == conn);
    if (idx != -1) _used.removeAt(idx);
    destroy(conn).ignore();
    _fillPendingOrEnsureMin();
  }

  Future<void> close() async {
    _destroyed = true;
    _stopReaping();
    while (_pendingAcquires.isNotEmpty) {
      _pendingAcquires.removeFirst().completeError(
        StateError('Connection pool closed'),
      );
    }
    for (final r in _free) {
      try {
        await destroy(r.conn);
      } catch (_) {}
    }
    _free.clear();
    // In-use connections will call release()/discard() when their query
    // finishes; release() destroys them because _destroyed == true.
  }

  // ─── Internals ────────────────────────────────────────────────────────────────

  Future<C> _createAndAcquire() async {
    _creating++;
    try {
      final conn = await create();
      _creating--;
      _used.add(PoolResource<C>(conn));
      _startReaping();
      return conn;
    } catch (e) {
      _creating--;
      rethrow;
    }
  }

  /// Create a connection for a pending waiter, or fall back to [_ensureMin].
  void _fillPendingOrEnsureMin() {
    if (_destroyed) return;
    if (_pendingAcquires.isNotEmpty && _total < max) {
      _creating++;
      create().then((conn) {
        _creating--;
        if (_destroyed) {
          destroy(conn).ignore();
          return;
        }
        final resource = PoolResource<C>(conn);
        if (_pendingAcquires.isNotEmpty) {
          _used.add(resource);
          _pendingAcquires.removeFirst().complete(conn);
          _startReaping();
        } else {
          _free.add(resource);
        }
      }).catchError((e) {
        _creating--;
        if (_pendingAcquires.isNotEmpty) {
          _pendingAcquires.removeFirst().completeError(e);
        }
      });
    } else {
      _ensureMin();
    }
  }

  /// Proactively fill the pool up to [min] total connections.
  void _ensureMin() {
    if (_destroyed) return;
    final needed = min - _total;
    for (var i = 0; i < needed; i++) {
      _creating++;
      create().then((conn) {
        _creating--;
        if (_destroyed) {
          destroy(conn).ignore();
          return;
        }
        if (_pendingAcquires.isNotEmpty) {
          _used.add(PoolResource<C>(conn));
          _pendingAcquires.removeFirst().complete(conn);
        } else {
          _free.add(PoolResource<C>(conn));
        }
        _startReaping();
      }).catchError((_) {
        _creating--;
      });
    }
  }

  void _startReaping() {
    _reapTimer ??= Timer.periodic(reapInterval, (_) => _reap());
  }

  void _stopReaping() {
    _reapTimer?.cancel();
    _reapTimer = null;
  }

  void _reap() {
    if (_destroyed) {
      _stopReaping();
      return;
    }
    final now = DateTime.now();

    // Keep enough free connections so total doesn't fall below [min].
    final minFree = (min - _used.length - _creating).clamp(0, _free.length);

    // Sort oldest-idle first so we evict the longest-sitting connections.
    _free.sort((a, b) => a.idleSince.compareTo(b.idleSince));
    while (_free.length > minFree) {
      final oldest = _free.first;
      if (now.difference(oldest.idleSince) >= idleTimeout) {
        _free.removeAt(0);
        destroy(oldest.conn).ignore();
      } else {
        break; // Even the oldest is not yet expired — stop.
      }
    }

    if (_free.isEmpty && _used.isEmpty && _creating == 0) {
      _stopReaping();
    }
    _ensureMin();
  }
}

import 'dart:async';

import 'package:knex_dart_mysql/src/pool.dart';
import 'package:test/test.dart';

// ─── Minimal fake connection ──────────────────────────────────────────────────

class _Conn {
  static int _seq = 0;
  final int id = _seq++;
  bool destroyed = false;
}

// ─── Pool factory helper ──────────────────────────────────────────────────────

/// Creates a pool whose [create] factory returns pre-built [_Conn] instances
/// from [conns] in order. [slow] adds an artificial 5 ms delay to creation
/// (useful for testing concurrent acquisition).
TarnPool<_Conn> _makePool({
  required List<_Conn> conns,
  int min = 0,
  int max = 1,
  Duration acquireTimeout = const Duration(milliseconds: 50),
  Duration idleTimeout = const Duration(seconds: 30),
  Duration reapInterval = const Duration(seconds: 60),
  bool slow = false,
}) {
  var idx = 0;
  return TarnPool<_Conn>(
    create: () async {
      if (slow) await Future.delayed(const Duration(milliseconds: 5));
      if (idx >= conns.length) throw StateError('factory exhausted');
      return conns[idx++];
    },
    destroy: (c) async => c.destroyed = true,
    min: min,
    max: max,
    acquireTimeout: acquireTimeout,
    idleTimeout: idleTimeout,
    reapInterval: reapInterval,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('TarnPool — timeout-race & edge cases', () {
    // ── 1. Core race: waiter times out, then the held connection is released ──
    //
    // Timeline:
    //   t=0   acquire(connA)  → succeeds immediately (pool empty → creates)
    //   t=0   acquire(connB)  → pool full → waiter queued, timeout=50ms
    //   t=60  timeout fires   → waiter removed from queue, TimeoutException
    //   t=60  release(connA)  → queue empty → connA goes to _free (no throw)
    //   t=60  acquire(connC)  → gets connA from _free immediately
    //
    // What we are guarding against:
    //   • release() calling .complete() on an already-timed-out waiter
    //   • StateError: "Future already completed"
    test('timeout-then-release: connection recycled, no StateError', () async {
      final connA = _Conn();
      final pool = _makePool(conns: [connA], acquireTimeout: const Duration(milliseconds: 50));

      // Acquire the only slot.
      final acquired = await pool.acquire();
      expect(acquired, same(connA));

      // Second acquire — will timeout after 50ms.
      // Attach the matcher immediately so the TimeoutException is handled
      // before Dart can report it as unhandled.
      final waiterFuture = pool.acquire();
      final waiterExpect = expectLater(
        waiterFuture,
        throwsA(isA<TimeoutException>()),
      );

      // Wait well past the timeout.
      await Future.delayed(const Duration(milliseconds: 120));
      await waiterExpect;

      // Release connA — waiter is gone; must NOT throw.
      // Connection should go to the free list.
      expect(() => pool.release(connA), returnsNormally);
      expect(connA.destroyed, isFalse); // not destroyed — recycled

      // Pool is healthy: the next acquire gets connA from the free list.
      final connC = await pool.acquire();
      expect(connC, same(connA));

      await pool.close();
    });

    // ── 2. Two concurrent waiters: release satisfies first, then second ──
    //
    // Ensures the FIFO queue delivers connections in order and that
    // completing one waiter does NOT accidentally complete the other.
    test('two concurrent waiters: FIFO order, no double-complete', () async {
      final conns = [_Conn(), _Conn()];
      // max=1 so the second acquire always waits.
      final pool = _makePool(
        conns: conns,
        max: 1,
        acquireTimeout: const Duration(milliseconds: 500),
      );

      final connA = await pool.acquire();

      // Queue two waiters simultaneously.
      final futureB = pool.acquire();
      final futureC = pool.acquire();

      // Release A → first waiter (B) should get it.
      pool.release(connA);
      final connB = await futureB;
      expect(connB, same(connA)); // same connection recycled

      // Release connB → second waiter (C) should get it.
      pool.release(connB);
      final connC = await futureC;
      expect(connC, same(connA)); // still the same connection

      await pool.close();
    });

    // ── 3. Close while waiter is pending ──
    //
    // Closing the pool must reject all pending waiters with StateError,
    // not leave them hanging or throw "already completed".
    test('close with pending waiter: StateError propagated cleanly', () async {
      final pool = _makePool(
        conns: [_Conn()],
        max: 1,
        acquireTimeout: const Duration(seconds: 10),
      );

      final connA = await pool.acquire();
      // Hold connA so the next acquire queues.
      // Attach the matcher immediately so the StateError is handled before
      // Dart can report it as unhandled.
      final pendingFuture = pool.acquire();
      final pendingExpect = expectLater(
        pendingFuture,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Connection pool closed',
          ),
        ),
      );

      await pool.close();
      await pendingExpect;

      // Release connA after close — should destroy it, not crash.
      expect(() => pool.release(connA), returnsNormally);
      expect(connA.destroyed, isTrue);
    });

    // ── 4. Min connections created on pool construction ──
    //
    // With min=2, the pool should eagerly create 2 connections.
    test('min connections warmed up on construction', () async {
      var createCount = 0;
      final pool = TarnPool<_Conn>(
        create: () async {
          createCount++;
          return _Conn();
        },
        destroy: (c) async => c.destroyed = true,
        min: 2,
        max: 5,
        acquireTimeout: const Duration(seconds: 1),
        idleTimeout: const Duration(seconds: 30),
        reapInterval: const Duration(seconds: 60),
      );

      // Allow async creation to complete.
      await Future.delayed(const Duration(milliseconds: 50));
      expect(createCount, greaterThanOrEqualTo(2));

      await pool.close();
    });

    // ── 5. Idle reaping destroys stale connections ──
    //
    // With idleTimeout=40ms and reapInterval=15ms, a connection that sits
    // idle for 80ms should be destroyed by the reaper.
    test('idle reaping: stale connection destroyed, pool stays usable', () async {
      final conn = _Conn();
      final pool = TarnPool<_Conn>(
        create: () async => conn,
        destroy: (c) async => c.destroyed = true,
        min: 0,
        max: 1,
        acquireTimeout: const Duration(seconds: 1),
        idleTimeout: const Duration(milliseconds: 40),
        reapInterval: const Duration(milliseconds: 15),
      );

      // Acquire and immediately release → moves to free list and starts reaper.
      final c = await pool.acquire();
      pool.release(c);

      // Wait for reaper to fire and destroy the idle connection.
      await Future.delayed(const Duration(milliseconds: 120));
      expect(conn.destroyed, isTrue);

      // Close cleanly (free list is empty — no double destroy).
      await pool.close();
    });
  });
}

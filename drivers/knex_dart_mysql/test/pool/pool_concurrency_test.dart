import 'dart:async';

import 'package:knex_dart_mysql/src/pool.dart';
import 'package:test/test.dart';

// ─── Minimal fake connection ──────────────────────────────────────────────────

class _Conn {
  static int _seq = 0;
  final int id = _seq++;
  bool destroyed = false;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('TarnPool — concurrency & pool-exhaustion races', () {
    // ── 1. Many concurrent acquires against a small pool ──
    //
    // 20 callers hammer a pool sized to 3. Each "holds" its connection for a
    // few ms, then releases. We assert:
    //   • all 20 acquires eventually resolve (no lost wakeups)
    //   • at no point are two callers holding the *same* physical connection
    //     (no double-allocation)
    //   • never more than `max` physical connections are created in total
    //     (the _creating/_total bookkeeping isn't over-counting or
    //     under-counting under interleaved create/acquire/release)
    test(
      'N concurrent acquires against pool smaller than N: all resolve, '
      'no double-allocation, never exceeds max physical connections',
      () async {
        const max = 3;
        const callers = 20;

        var createCount = 0;
        final pool = TarnPool<_Conn>(
          create: () async {
            createCount++;
            // Small randomized-ish delay via alternating timings to
            // encourage interleaving between concurrent creates.
            await Future.delayed(Duration(milliseconds: 2 + (createCount % 3)));
            return _Conn();
          },
          destroy: (c) async => c.destroyed = true,
          min: 0,
          max: max,
          acquireTimeout: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 30),
          reapInterval: const Duration(seconds: 60),
        );

        final held = <int>{};
        final maxConcurrentHeld = <int>[];

        Future<void> worker() async {
          final conn = await pool.acquire();
          expect(
            held.contains(conn.id),
            isFalse,
            reason:
                'connection ${conn.id} was handed to two callers at once',
          );
          held.add(conn.id);
          maxConcurrentHeld.add(held.length);
          // Simulate a bit of work on the connection.
          await Future.delayed(const Duration(milliseconds: 3));
          held.remove(conn.id);
          pool.release(conn);
        }

        await Future.wait(List.generate(callers, (_) => worker()));

        expect(
          maxConcurrentHeld.reduce((a, b) => a > b ? a : b),
          lessThanOrEqualTo(max),
          reason: 'more than $max connections were concurrently checked out',
        );
        expect(
          createCount,
          lessThanOrEqualTo(max),
          reason:
              'pool created more physical connections than max allows — '
              '_total/_creating bookkeeping is over-counting capacity',
        );

        await pool.close();
      },
    );

    // ── 2a. discard() never recycles a broken connection ──
    test('discard() removes and destroys — never handed out again', () async {
      final conns = [_Conn(), _Conn()];
      var idx = 0;
      final pool = TarnPool<_Conn>(
        create: () async => conns[idx++],
        destroy: (c) async => c.destroyed = true,
        min: 0,
        max: 1,
        acquireTimeout: const Duration(seconds: 1),
        idleTimeout: const Duration(seconds: 30),
        reapInterval: const Duration(seconds: 60),
      );

      final connA = await pool.acquire();
      expect(connA, same(conns[0]));

      pool.discard(connA);
      expect(connA.destroyed, isTrue);

      // Next acquire must create a fresh connection, not resurrect connA.
      final connB = await pool.acquire();
      expect(connB, same(conns[1]));
      expect(connB, isNot(same(connA)));

      await pool.close();
    });

    // ── 2b. validate() rejects an unhealthy connection on release ──
    //
    // If `validate` is configured and a connection fails validation when
    // released, the pool must destroy it rather than put it back in the
    // free list as "healthy". (knex_dart_mysql's MySQLClient never wires up
    // `validate` in production — it relies on explicit release()/discard()
    // calls driven by a try/finally `success` flag instead — but the pool's
    // own `validate` contract must still hold for anyone who does use it.)
    test(
      'validate() failing on release() destroys the connection, does not '
      'recycle it into the free list',
      () async {
        final badConn = _Conn();
        final goodConn = _Conn();
        final conns = [badConn, goodConn];
        var idx = 0;
        final pool = TarnPool<_Conn>(
          create: () async => conns[idx++],
          destroy: (c) async => c.destroyed = true,
          // Reject badConn specifically; anything else validates fine.
          validate: (c) => !identical(c, badConn),
          min: 0,
          max: 1,
          acquireTimeout: const Duration(seconds: 1),
          idleTimeout: const Duration(seconds: 30),
          reapInterval: const Duration(seconds: 60),
        );

        final acquired = await pool.acquire();
        expect(acquired, same(badConn));

        pool.release(acquired);
        // Must be destroyed immediately by release()'s validate check —
        // not silently reused as a "healthy" free connection.
        expect(badConn.destroyed, isTrue);

        final next = await pool.acquire();
        expect(next, same(goodConn));
        expect(next, isNot(same(badConn)));

        await pool.close();
      },
    );

    // ── 3. Multiple concurrent waiters, pool closed while all are pending ──
    //
    // Extends pool_timeout_test.dart's single-waiter close case to several
    // simultaneous waiters: none may hang forever, none may throw
    // unhandled, and all must reject with the same StateError.
    test(
      'close() with several concurrent pending waiters: all reject '
      'cleanly, none hang, none throw unhandled',
      () async {
        final pool = TarnPool<_Conn>(
          create: () async => _Conn(),
          destroy: (c) async => c.destroyed = true,
          min: 0,
          max: 1,
          acquireTimeout: const Duration(seconds: 10),
          idleTimeout: const Duration(seconds: 30),
          reapInterval: const Duration(seconds: 60),
        );

        // Take the only slot so subsequent acquires queue.
        final connA = await pool.acquire();

        final waiterFutures = List.generate(5, (_) => pool.acquire());
        final waiterExpectations = [
          for (final f in waiterFutures)
            expectLater(
              f,
              throwsA(
                isA<StateError>().having(
                  (e) => e.message,
                  'message',
                  'Connection pool closed',
                ),
              ),
            ),
        ];

        await pool.close().timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('close() hung with pending waiters'),
        );

        await Future.wait(waiterExpectations).timeout(
          const Duration(seconds: 2),
          onTimeout: () => fail('a pending waiter never settled after close()'),
        );

        pool.release(connA); // must not throw even though pool is closed
        expect(connA.destroyed, isTrue);
      },
    );

    // ── 4. acquire() called after close() has already completed ──
    test(
      'acquire() after close() has fully completed throws immediately',
      () async {
        final pool = TarnPool<_Conn>(
          create: () async => _Conn(),
          destroy: (c) async => c.destroyed = true,
          min: 0,
          max: 1,
          acquireTimeout: const Duration(seconds: 1),
          idleTimeout: const Duration(seconds: 30),
          reapInterval: const Duration(seconds: 60),
        );

        await pool.close();

        await expectLater(
          pool.acquire(),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Connection pool is closed',
            ),
          ),
        );
      },
    );

    // ── 5. BUG (fixed): acquire() racing an in-flight create with close() ──
    //
    // Timeline before the fix:
    //   t=0    acquire() called → pool empty, under capacity → starts an
    //          async create() (connection creation takes 30ms)
    //   t=0    close() called → _destroyed = true; nothing to await since
    //          _free/_used are both empty (the connection is still being
    //          created) → close() future resolves almost immediately
    //   t=30   create() resolves → _createAndAcquire() unconditionally did
    //          `_used.add(...)` and returned the live connection to the
    //          original acquire() caller — i.e. a caller received a
    //          successfully-acquired, live connection from a pool whose
    //          close() had *already completed*. The connection was marked
    //          "in use" inside a pool that claimed to be fully destroyed,
    //          and nothing would ever destroy it (release()/discard() were
    //          never called by this test), and _startReaping() would even
    //          resurrect a periodic Timer on the destroyed pool.
    //
    // This test asserts the fixed contract: once close() has resolved, no
    // in-flight create may be silently handed out as a successful acquire.
    // The acquire() must instead fail, and the freshly-created connection
    // must be destroyed by the pool itself (not leaked).
    test(
      'acquire() racing close(): in-flight create is destroyed and the '
      'acquire rejects, instead of silently succeeding after close()',
      () async {
        final createdConns = <_Conn>[];
        final pool = TarnPool<_Conn>(
          create: () async {
            await Future.delayed(const Duration(milliseconds: 30));
            final c = _Conn();
            createdConns.add(c);
            return c;
          },
          destroy: (c) async => c.destroyed = true,
          min: 0,
          max: 1,
          acquireTimeout: const Duration(seconds: 5),
          idleTimeout: const Duration(seconds: 30),
          reapInterval: const Duration(seconds: 60),
        );

        // Starts _createAndAcquire(); create() is now in flight.
        final acquireFuture = pool.acquire();
        // Attach the matcher immediately so the rejection is handled before
        // Dart can report it as unhandled.
        final acquireExpect = expectLater(
          acquireFuture,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Connection pool closed',
            ),
          ),
        );

        // Nothing to await (free/used are empty) — close() resolves right
        // away, well before the in-flight create() finishes at t=30ms.
        await pool.close();

        await acquireExpect;

        // The connection created during the race must have been destroyed
        // by the pool itself, not handed out live and left dangling.
        expect(createdConns, hasLength(1));
        expect(
          createdConns.single.destroyed,
          isTrue,
          reason:
              'connection created after close() must be destroyed, not '
              'leaked as a live, unreleasable "in use" resource',
        );
      },
    );
  });
}

import 'dart:async';

import 'domain_event.dart';

/// An in-process broadcast stream of [DomainEvent]s.
///
/// Delivery is asynchronous, so a publisher is never blocked or broken by a
/// listener. A listener that throws is reported to the zone, not to the
/// publisher.
class DomainEventBus {
  DomainEventBus() : _controller = StreamController<DomainEvent>.broadcast();

  final StreamController<DomainEvent> _controller;

  /// Every event, in publish order.
  Stream<DomainEvent> get events => _controller.stream;

  /// Only events of type [E].
  Stream<E> on<E extends DomainEvent>() =>
      _controller.stream.where((e) => e is E).cast<E>();

  bool get isClosed => _controller.isClosed;

  /// Publishes [event]. After [dispose] this is a no-op.
  void publish(DomainEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  /// Closes the bus. Existing listeners receive done.
  Future<void> dispose() => _controller.close();
}

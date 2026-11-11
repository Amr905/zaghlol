// T-047: a tiny timer seam so retry, coalesce and debounce schedules are
// testable without real time.

import 'dart:async';

typedef CancelTimer = void Function();

abstract interface class CaptureScheduler {
  /// Runs [callback] once after [delay]; the result cancels it.
  CancelTimer after(Duration delay, void Function() callback);
}

final class TimerCaptureScheduler implements CaptureScheduler {
  const TimerCaptureScheduler();

  @override
  CancelTimer after(Duration delay, void Function() callback) {
    final t = Timer(delay, callback);
    return t.cancel;
  }
}

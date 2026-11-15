// T-120: the seam between the voice logger and the OS speech recognizer
// (ADR-010). Widget and controller tests fake it; `data/` implements it with
// speech_to_text. Nothing here stores or logs audio or transcripts.

/// Why recognition could not start or ended without text.
enum SpeechError {
  /// The microphone / speech permission is denied.
  permissionDenied,

  /// No recognizer, or (when [SpeechPort.start] asked for on-device only) no
  /// on-device model for the language (EC-32, OQ-06).
  unavailable,

  /// Listening ended with nothing recognized.
  noSpeech,

  /// Any other recognizer failure.
  other,
}

/// What the recognizer reports while listening. All callbacks are optional
/// to keep fakes short.
class SpeechSink {
  const SpeechSink({
    required this.onText,
    required this.onLevel,
    required this.onEnded,
    required this.onError,
  });

  /// The transcript so far (grows; `isFinal` on the last one).
  final void Function(String text, {required bool isFinal}) onText;

  /// Input level, 0..1 (drives the wings pulse).
  final void Function(double level) onLevel;

  /// The session is over (silence timeout, max length, or [SpeechPort.stop]).
  final void Function() onEnded;

  final void Function(SpeechError error) onError;
}

abstract interface class SpeechPort {
  /// True only when the OS confirms recognition for [localeId] runs on the
  /// device without the network (Android API 31+ with the language installed
  /// on 33+; iOS `supportsOnDeviceRecognition`). Unknown means false: the
  /// plugin's `onDevice` flag alone can fall back to the network on Android.
  Future<bool> supportsOnDevice(String localeId);

  /// Starts listening with locale [localeId] (`ar_EG`, `en_US`).
  ///
  /// With [onDevice] true the recognizer must not use the network: if it
  /// cannot, [SpeechError.unavailable] is reported through [SpeechSink.onError]
  /// (or thrown as the returned error) and nothing is sent anywhere. Returns
  /// null when listening started, else why it did not.
  Future<SpeechError?> start({
    required String localeId,
    required bool onDevice,
    required SpeechSink sink,
    required Duration pauseFor,
    required Duration listenFor,
  });

  /// Stops listening and delivers the final transcript.
  Future<void> stop();

  /// Stops listening and drops everything.
  Future<void> cancel();
}

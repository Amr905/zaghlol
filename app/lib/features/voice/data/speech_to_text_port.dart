// T-120: [SpeechPort] over the speech_to_text plugin (ADR-010, FR-VOI-01).
// The only file that imports the plugin (a privacy test checks that). Audio
// stays inside the OS recognizer; this app never records to a file. Transcripts
// are handed to the sink and never logged.

import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../application/speech_port.dart';

class SpeechToTextPort implements SpeechPort {
  SpeechToTextPort([SpeechToText? engine, MethodChannel? host])
    : _stt = engine ?? SpeechToText(),
      _host = host ?? const MethodChannel('zaghlol/speech');

  final MethodChannel _host;

  @override
  Future<bool> supportsOnDevice(String localeId) async {
    try {
      return await _host.invokeMethod<bool>('onDeviceSupport', {
            'locale': localeId,
          }) ??
          false;
    } on Object {
      return false;
    }
  }

  final SpeechToText _stt;
  SpeechSink? _sink;
  bool _ended = false;

  Future<bool> _ensureInit() => _stt.initialize(
    onError: _onError,
    onStatus: _onStatus,
    debugLogging: false,
  );

  @override
  Future<SpeechError?> start({
    required String localeId,
    required bool onDevice,
    required SpeechSink sink,
    required Duration pauseFor,
    required Duration listenFor,
  }) async {
    _sink = sink;
    _ended = false;
    try {
      if (!await _ensureInit()) {
        return await _stt.hasPermission
            ? SpeechError.unavailable
            : SpeechError.permissionDenied;
      }
      await _stt.listen(
        onResult: _onResult,
        onSoundLevelChange: _onLevel,
        listenOptions: SpeechListenOptions(
          onDevice: onDevice,
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
          pauseFor: pauseFor,
          listenFor: listenFor,
          localeId: localeId,
        ),
      );
      return null;
    } on Object {
      return SpeechError.other;
    }
  }

  void _onResult(SpeechRecognitionResult r) =>
      _sink?.onText(r.recognizedWords, isFinal: r.finalResult);

  void _onLevel(double db) {
    // Android reports about -2..10, iOS about -50..0; clamp both to 0..1.
    final v = db > 0 ? (db + 2) / 12 : (db + 50) / 50;
    _sink?.onLevel(v.clamp(0.0, 1.0));
  }

  void _onStatus(String status) {
    if ((status == 'done' || status == 'notListening') && !_ended) {
      _ended = true;
      _sink?.onEnded();
    }
  }

  void _onError(SpeechRecognitionError e) {
    final err = switch (e.errorMsg) {
      'error_language_unavailable' ||
      'error_language_not_supported' ||
      'error_server_disconnected' ||
      'error_network' => SpeechError.unavailable,
      'error_permission' => SpeechError.permissionDenied,
      'error_no_match' || 'error_speech_timeout' => SpeechError.noSpeech,
      _ => SpeechError.other,
    };
    _sink?.onError(err);
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } on Object {
      // Already stopped.
    }
  }

  @override
  Future<void> cancel() async {
    _sink = null;
    try {
      await _stt.cancel();
    } on Object {
      // Already stopped.
    }
  }
}

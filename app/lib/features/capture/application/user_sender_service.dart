// T-047 (design note §1, "Senders"): the one write path for "always capture
// this sender". Validation runs before any DB write; a channel conflict
// (FU-096 m-2) is a typed result, never an exception, and never counts the
// other channel. The caller (picker, S-61) then calls
// `CaptureCoordinator.onRuleChanged()` so the Guard config is rewritten.

import '../../../core/db/daos/capture_controls_dao.dart';
import '../domain/sender_validation.dart';

sealed class UserSenderOutcome {
  const UserSenderOutcome();
}

final class UserSenderSaved extends UserSenderOutcome {
  const UserSenderSaved();
}

final class UserSenderRefused extends UserSenderOutcome {
  const UserSenderRefused(this.reason);

  final SenderRefusal reason;
}

/// The sender is stored on the other channel; nothing changed.
final class UserSenderConflict extends UserSenderOutcome {
  const UserSenderConflict();
}

final class UserSenderService {
  UserSenderService(this._dao, {int Function()? nowMs})
    : _nowMs = nowMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final CaptureControlsDao _dao;
  final int Function() _nowMs;

  Future<UserSenderOutcome> setAlwaysCapture({
    required UserSenderChannel channel,
    required String sender,
    required bool always,
  }) async {
    if (always) {
      // A sender that is already stored on this channel is a re-save, not a
      // new one for the cap.
      var existing = 0;
      if (channel == UserSenderChannel.notification) {
        final row = await _dao.sender(sender);
        final isResave =
            row != null &&
            row.channel == SenderChannel.notification &&
            row.alwaysCapture == 1;
        existing = isResave
            ? 0
            : await _dao.alwaysCaptureCount(SenderChannel.notification);
      }
      final refusal = validateUserSender(
        channel,
        sender,
        existingNotificationSenders: existing,
      );
      if (refusal != null) return UserSenderRefused(refusal);
    }
    final result = await _dao.setAlwaysCapture(
      sender: sender,
      channel: switch (channel) {
        UserSenderChannel.sms => SenderChannel.sms,
        UserSenderChannel.notification => SenderChannel.notification,
      },
      always: always,
      at: _nowMs(),
    );
    return switch (result) {
      SenderWritten() => const UserSenderSaved(),
      ChannelConflict() => const UserSenderConflict(),
    };
  }
}

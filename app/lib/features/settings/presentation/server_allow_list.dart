// T-162: what Zaghlol's server may know (BR-SYNC-03 allow-list, D-45, D-55,
// D-62, security-model 2a). The privacy screen renders this list, so a new
// allow-list entry cannot ship without its copy: each entry maps to one l10n
// key pair in `privacy_screen.dart` (a switch with no default).

enum ServerKnows {
  appId,
  purchase,
  signIn,
  merchants,
  versions,
  attestation,
  bankRequest,
  timeNonce,

  /// D-55/D-62: iPhone only.
  seatKeys,

  /// 2a disclosures.
  deleteKeepsKeys,
  supportNotice,
  supportRows;

  /// True when the entry applies on [platform] (`ios` / `android`).
  bool appliesOn(String platform) => switch (this) {
    seatKeys || deleteKeepsKeys => platform == 'ios',
    _ => true,
  };
}

/// The entries shown on [platform], in display order.
List<ServerKnows> serverAllowList(String platform) => [
  for (final k in ServerKnows.values)
    if (k.appliesOn(platform)) k,
];

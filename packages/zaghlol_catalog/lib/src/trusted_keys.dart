// T-030: the public keys the app accepts for the bundled seed.
//
// `s0000a` is the DEV key: its private half is committed in
// tools/catalog_build/dev/ so anyone can rebuild the seed. It proves the
// seed was not corrupted or edited by accident; it does not authenticate
// the build. `verifySeedSignature` refuses dev kids (`s0000x`) unless the
// caller passes `allowDevKeys: true` (the app does so only outside release
// mode), so a release build fails closed. Before a store release the seed
// must come from the backend (KMS-signed, FU-078) and `s0000a` be removed.
// The kid differs from the backend's local dev ring (`s0000d`) on purpose.

import 'seed_signature.dart';

/// The trusted seed keys, in kid order.
List<SeedTrustedKey> bundledSeedKeys() => [
  SeedTrustedKey.fromJwk(
    kid: 's0000a',
    x: 't8Y4R3c9L4KX-HxirVjibAkbYQJDsCadxWJZT1QScAU',
    y: 'cSHnLXgsWS6V32igQB0DnPqQv8-IqoT8uzkuVL0M2VY',
  ),
];

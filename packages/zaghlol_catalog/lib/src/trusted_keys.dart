// T-030: the public keys the app accepts for the bundled seed.
//
// `s0000d` is the DEV key: its private half is committed in
// tools/catalog_build/dev/ so anyone can rebuild the seed. It proves the
// seed was not corrupted or edited by accident; it does not authenticate
// the build. Before a store release the seed must be re-signed with a
// production Sync key (kid `s####x`, T-123) whose public half is added here
// and `s0000d` removed (follow-up FU-078; a test pins the current set so
// the swap is a deliberate change).

import 'seed_signature.dart';

/// The trusted seed keys, in kid order.
List<SeedTrustedKey> bundledSeedKeys() => [
  SeedTrustedKey.fromJwk(
    kid: 's0000d',
    x: 'rp7hYUeRmwjdAaFCtDYOvJDoVSWbl60bxqFREiU6I7M',
    y: 'SWup7wPmqVcDfAQk-a8rHPJtGgp-El2Ecj3oT2IRPpM',
  ),
];

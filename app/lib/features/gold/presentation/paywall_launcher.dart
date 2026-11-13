// T-146: opens S-68 when a gate blocks (T-119 `paywallTriggerProvider`).
// A tap on a locked item is the user's own request, so it is never capped;
// only prompts the app raises by itself go through `UpsellCap` (A-22).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../application/gating.dart';
import 'paywall_screen.dart';

/// Root-scope override: gates open the paywall on [navigatorKey].
Override paywallTriggerOverride(GlobalKey<NavigatorState> navigatorKey) =>
    paywallTriggerProvider.overrideWith(
      (ref) => (GoldCapability _) {
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        unawaited(
          nav.push<bool>(
            MaterialPageRoute<bool>(
              fullscreenDialog: true,
              builder: (_) => const PaywallScreen(),
            ),
          ),
        );
      },
    );

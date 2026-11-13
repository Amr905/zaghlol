// T-147: opens S-69 from the Gold messages ("Sign in" buttons, T-146's
// `goldSignInOpenerProvider`). Root-scope override, like T-146's paywall
// trigger.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../gold/presentation/gold_ui_ports.dart';
import 'account_screen.dart';

Override goldSignInOpenerOverride(GlobalKey<NavigatorState> navigatorKey) =>
    goldSignInOpenerProvider.overrideWith(
      (ref) => () {
        final nav = navigatorKey.currentState;
        if (nav == null) return;
        unawaited(
          nav.push<void>(
            MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
          ),
        );
      },
    );

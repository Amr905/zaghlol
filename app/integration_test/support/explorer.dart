// TEST-explorer: a generic "tap everything" engine for widget and
// integration tests. It walks the live element tree, finds every tappable
// widget on the current screen, taps each one, and records:
//   - exceptions and RenderFlex overflows (FlutterError.onError),
//   - dead taps (the screen's text/route fingerprint did not change),
//   - navigation dead ends (the new screen cannot be left again),
//   - the app leaving the foreground.
// It descends into screens a tap opens (depth-first, capped), takes a
// screenshot of every screen the first time it appears, and goes back after
// each tap. It never types text and skips the labels in `deny`.
//
// The engine only depends on flutter_test, so a plain widget test can run
// it on a tiny app (test/integration_support/explorer_engine_test.dart).

import 'package:flutter/foundation.dart'
    show FlutterError, FlutterErrorDetails, FlutterExceptionHandler;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// One problem the explorer found.
final class ExplorerIssue {
  const ExplorerIssue(this.kind, this.where, this.detail);

  /// `exception`, `overflow`, `dead-tap`, `dead-end`, `left-app`, `restore`.
  final String kind;
  final String where;
  final String detail;
}

/// One tap and what it did.
final class TapRecord {
  TapRecord(this.kind, this.label, this.outcome);
  final String kind;
  final String label;
  String outcome;
}

/// What the explorer saw on one screen.
final class ScreenRecord {
  ScreenRecord(this.index, this.title, this.kind, this.depth, this.shot);
  final int index;
  final String title;
  final String kind;
  final int depth;
  final String shot;
  final List<TapRecord> taps = [];
  final List<ExplorerIssue> issues = [];
  int candidates = 0;
  bool capped = false;
}

final class _Route {
  _Route(this.route, this.element, this.kind);
  final ModalRoute<Object?> route;
  final Element element;
  final String kind;
  int get id => identityHashCode(route);
}

final class _Snapshot {
  _Snapshot(this.fingerprint, this.routes);
  final String fingerprint;
  final List<_Route> routes;
  Set<int> get ids => {for (final r in routes) r.id};
}

/// A screen being explored: its routes when it is showing, and how to bring
/// it back after a tap closed it.
final class _Ctx {
  _Ctx(this.base, this.reopen);
  _Snapshot base;
  final Future<void> Function()? reopen;
}

final class _Cand {
  _Cand(this.element, this.kind, this.label, this.center, this.key);
  final Element element;
  final String kind;
  final String label;
  final Offset center;
  final String key;
}

typedef ShotFn = Future<void> Function(String name);

class Explorer {
  Explorer({
    required this.tester,
    required this.shot,
    required this.deadline,
    required this.goHome,
    this.selectTab,
    this.deny = const {},
    this.navLabels = const {},
    this.maxDepth = 3,
    this.maxTapsPerScreen = 60,
    this.maxTapsPerDialog = 15,
    this.onUpdate,
    this.log = _print,
  });

  final WidgetTester tester;
  final ShotFn shot;
  final DateTime deadline;

  /// Brings the app back to its first tab root (used after a lost restore).
  final Future<void> Function() goHome;

  /// Selects tab [i]; used when a tap switches tabs.
  final Future<void> Function(int i)? selectTab;

  /// Labels that are never tapped (destructive or leaving the app).
  final Set<String> deny;

  /// Labels of icon-only back/close buttons: leaving a screen is covered by
  /// the pop after each tap, so they are not tapped as controls.
  final Set<String> navLabels;
  final int maxDepth;
  final int maxTapsPerScreen;
  final int maxTapsPerDialog;
  final void Function(String markdown)? onUpdate;
  final void Function(String line) log;

  static void _print(String line) {
    // ignore: avoid_print
    print(line);
  }

  final List<ScreenRecord> screens = [];
  final Set<String> _seen = {};
  final List<FlutterErrorDetails> _errors = [];
  FlutterExceptionHandler? _previousOnError;
  ScreenRecord? _cur;
  String _curWhere = '';
  int _taps = 0;
  int _dead = 0;
  bool _stopped = false;

  bool get timedOut => DateTime.now().isAfter(deadline);

  int get totalIssues => [for (final s in screens) ...s.issues].length;

  /// Routes error reports into the explorer for the duration of the run.
  void install() {
    _previousOnError = FlutterError.onError;
    FlutterError.onError = _errors.add;
  }

  void uninstall() {
    FlutterError.onError = _previousOnError;
  }

  // ------------------------------------------------------------ driver

  /// Explores the screen that is showing now as [name] (a tab root, say).
  /// [reopen] brings that screen back when a tap closed it.
  Future<void> exploreCurrent(
    String name, {
    Future<void> Function()? reopen,
    int tabIndex = 0,
    int depth = 0,
  }) async {
    await _settle();
    await _screen(name, depth, reopen, tabIndex, force: true);
  }

  Future<void> _screen(
    String name,
    int depth,
    Future<void> Function()? reopen,
    int tabIndex, {
    bool force = false,
  }) async {
    final snap = _snapshot();
    final ctx = _Ctx(snap, reopen);
    final top = snap.routes.isEmpty ? null : snap.routes.last;
    final title = force ? name : _titleOf(top) ?? name;
    final key = '${top?.kind}|$title';
    if (!force && !_seen.add(key)) return;
    if (force) _seen.add(key);
    final index = screens.length + 1;
    final file = 'x-${index.toString().padLeft(2, '0')}';
    final rec = ScreenRecord(index, title, top?.kind ?? 'none', depth, file);
    screens.add(rec);
    log('EXPLORER_SCREEN $index $title (${rec.kind}, depth $depth)');
    await shot(file);
    _flushErrors(rec, 'opening');
    final isDialog = rec.kind != 'Scaffold';
    final cap = isDialog ? maxTapsPerDialog : maxTapsPerScreen;
    final done = <String>{};
    var stalePasses = 0;
    for (var pass = 0; pass < 6 && !_stopped; pass++) {
      var progressed = false;
      while (!_stopped && !timedOut) {
        if (rec.taps.length >= cap) {
          rec.capped = true;
          break;
        }
        var cands = _candidates();
        var next = cands.where((c) => !done.contains(c.key)).toList();
        if (next.isEmpty && (progressed || pass == 0)) {
          // A page still sliding in or out hides its buttons from hit tests.
          await _settle(minMs: 600);
          cands = _candidates();
          next = cands.where((c) => !done.contains(c.key)).toList();
        }
        if (cands.length > rec.candidates) rec.candidates = cands.length;
        if (next.isEmpty) break;
        final c = next.first;
        done.add(c.key);
        progressed = true;
        final ok = await _tap(rec, c, ctx, depth, tabIndex);
        if (!ok) return;
      }
      if (rec.capped || timedOut) break;
      // Look further down the page.
      final before = _candidates().map((c) => c.key).toSet();
      if (!await _scrollDown()) break;
      final after = _candidates().map((c) => c.key).toSet();
      if (after.difference(before).isEmpty && !progressed) {
        if (++stalePasses > 1) break;
      }
    }
    onUpdate?.call(markdown());
  }

  Future<bool> _tap(
    ScreenRecord rec,
    _Cand c,
    _Ctx ctx,
    int depth,
    int tabIndex,
  ) async {
    final pre = _snapshot();
    _errors.clear();
    _taps++;
    final record = TapRecord(c.kind, c.label, '');
    _cur = rec;
    _curWhere = '${c.kind} "${c.label}"';
    rec.taps.add(record);
    await tester.tapAt(c.center);
    await _settle();
    var post = _snapshot();
    // Exceptions first: they matter even when the tap did something.
    final threw = _flushErrors(rec, '${c.kind} "${c.label}"');
    final state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      rec.issues.add(
        ExplorerIssue(
          'left-app',
          '${c.kind} "${c.label}"',
          'the app left the foreground ($state)',
        ),
      );
      record.outcome = 'left the app';
      await _waitForeground();
    }
    bool sameRoutes(_Snapshot x) =>
        x.ids.length == pre.ids.length && x.ids.containsAll(pre.ids);
    if (sameRoutes(post) && post.fingerprint == pre.fingerprint) {
      // Give slow work (a database read, a page sliding away) one more look.
      await _pump(const Duration(milliseconds: 700));
      post = _snapshot();
    }
    final newRoutes = post.routes
        .where((r) => !pre.ids.contains(r.id))
        .toList();
    final goneRoutes = pre.routes
        .where((r) => !post.ids.contains(r.id))
        .toList();
    if (newRoutes.isEmpty && goneRoutes.isEmpty) {
      if (post.fingerprint == pre.fingerprint) {
        if (threw) {
          record.outcome = 'threw';
        } else {
          _dead++;
          if (record.outcome.isEmpty) record.outcome = 'NOTHING HAPPENED';
          rec.issues.add(
            ExplorerIssue(
              'dead-tap',
              '${c.kind} "${c.label}"',
              'no route, text or state change after the tap',
            ),
          );
        }
      } else if (record.outcome.isEmpty) {
        record.outcome = 'changed the screen';
      }
      return true;
    }
    if (newRoutes.isNotEmpty) {
      final top = newRoutes.last;
      final childTitle = _titleOf(top) ?? '?';
      if (top.route.isFirst && selectTab != null) {
        record.outcome = 'switched tab';
      } else {
        final fresh = !_seen.contains('${top.kind}|$childTitle');
        record.outcome = fresh
            ? 'opens "$childTitle" (${top.kind})'
            : 'opens "$childTitle" (seen)';
        if (fresh && depth < maxDepth && !_stopped && !timedOut) {
          Future<void> again() async {
            final got = await _restore(rec, ctx.base, ctx.reopen, tabIndex);
            if (got == null) return;
            ctx.base = got;
            await _tapByKey(c.key);
          }

          await _screen(childTitle, depth + 1, again, tabIndex);
        }
      }
    } else {
      record.outcome = 'closed ${goneRoutes.last.kind}';
    }
    final got = await _restore(rec, pre, ctx.reopen, tabIndex);
    if (got == null) return false;
    // Reopening makes new route objects: the screen's baseline moves.
    if (got.ids.length != pre.ids.length || !got.ids.containsAll(pre.ids)) {
      ctx.base = got;
    }
    return true;
  }

  /// Gets back to [target]'s routes (or an equal-sized set after a
  /// [reopen]). Null when it could not; the caller stops exploring.
  Future<_Snapshot?> _restore(
    ScreenRecord rec,
    _Snapshot target,
    Future<void> Function()? reopen,
    int tabIndex,
  ) async {
    var reopened = false;
    for (var i = 0; i < 6; i++) {
      final now = _snapshot();
      final want = target.ids;
      final have = now.ids;
      if (have.length == want.length && have.containsAll(want)) return now;
      // After a reopen the routes are new objects of the same shape.
      if (reopened && have.length == want.length) return now;
      final extra = now.routes.where((r) => !want.contains(r.id)).toList();
      if (extra.isNotEmpty) {
        final top = extra.last;
        if (top.route.isFirst && selectTab != null) {
          await selectTab!(tabIndex);
        } else if (top.route.navigator == null) {
          break;
        } else {
          top.route.navigator!.pop();
        }
        await _settle(minMs: 500);
        _errors.clear();
        continue;
      }
      // A route we started on is gone (the sheet closed itself, say).
      if (reopen != null && !reopened) {
        reopened = true;
        await reopen();
        await _settle(minMs: 250);
        continue;
      }
      break;
    }
    final now = _snapshot();
    if (now.ids.length == target.ids.length &&
        (reopened || now.ids.containsAll(target.ids))) {
      return now;
    }
    final stuck = now.routes
        .where((r) => !target.ids.contains(r.id))
        .isNotEmpty;
    rec.issues.add(
      stuck
          // A screen that cannot be left: a real navigation dead end.
          ? ExplorerIssue(
              'dead-end',
              rec.title,
              'a screen stayed open after going back; went Home',
            )
          // The tap changed what the screen shows (a chosen category, say),
          // so the control that opened it is gone: not a bug.
          : ExplorerIssue(
              'restore',
              rec.title,
              'the screen could not be reopened after its state changed',
            ),
    );
    await goHome();
    await _settle(minMs: 300);
    return null;
  }

  Future<void> _tapByKey(String key) async {
    for (var i = 0; i < 4; i++) {
      // A page that just slid back in is not hit-testable for a moment.
      await _settle(minMs: 500);
      final hit = _candidates().where((c) => c.key == key).toList();
      if (hit.isNotEmpty) {
        await tester.tapAt(hit.first.center);
        await _settle(minMs: 500);
        return;
      }
      if (i > 0 && !await _scrollDown()) return;
    }
  }

  bool _flushErrors(ScreenRecord rec, String where) {
    if (_errors.isEmpty) return false;
    final seen = <String>{};
    for (final d in _errors) {
      final text = d.exceptionAsString().split('\n').first;
      var line = text.length > 160 ? '${text.substring(0, 160)}...' : text;
      // Where it happened: the widget (and file:line) Flutter names.
      final where2 = RegExp(r'error-causing widget was:\s*\n\s*(.+)')
          .firstMatch(d.toString());
      if (where2 != null) {
        final w = where2.group(1)!;
        line = '$line @ ${w.length > 140 ? w.substring(w.length - 140) : w}';
      }
      if (!seen.add(line)) continue;
      final overflow = text.contains('overflowed');
      rec.issues.add(
        ExplorerIssue(overflow ? 'overflow' : 'exception', where, line),
      );
      log(
        'EXPLORER_ISSUE ${overflow ? 'overflow' : 'exception'} '
        '${rec.title} / $where / $line',
      );
    }
    _errors.clear();
    return true;
  }

  // ------------------------------------------------------------ settle

  Future<void> _pump(Duration d) async {
    var left = d.inMilliseconds;
    while (left > 0) {
      final step = left < 100 ? left : 100;
      await tester.pump(Duration(milliseconds: step));
      left -= step;
    }
  }

  Future<void> _settle({int minMs = 300}) async {
    await _pump(Duration(milliseconds: minMs));
    var last = _snapshot().fingerprint;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
      final now = _snapshot().fingerprint;
      if (now == last) return;
      last = now;
    }
  }

  Future<void> _waitForeground() async {
    final end = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 250));
      final s = WidgetsBinding.instance.lifecycleState;
      if (s == null || s == AppLifecycleState.resumed) return;
    }
  }

  // ------------------------------------------------------------ tree

  void _walk(Element root, bool Function(Element) visit) {
    void go(Element e) {
      final w = e.widget;
      if (w is Offstage && w.offstage) return;
      if (!visit(e)) return;
      e.visitChildren(go);
    }

    go(root);
  }

  _Snapshot _snapshot() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return _Snapshot('', const []);
    final sb = StringBuffer();
    final routes = <_Route>[];
    final seenRoutes = <int>{};
    _walk(root, (e) {
      final w = e.widget;
      if (w is Text) {
        sb
          ..write(w.data ?? w.textSpan?.toPlainText() ?? '')
          ..write('\u0001');
      } else if (w is Switch) {
        sb.write('S${w.value}\u0001');
      } else if (w is Checkbox) {
        sb.write('C${w.value}\u0001');
      } else if (w is ChoiceChip) {
        sb.write('H${w.selected}\u0001');
      } else if (w is FilterChip) {
        sb.write('F${w.selected}\u0001');
      } else if (w is Icon) {
        sb.write('I${w.icon?.codePoint}\u0001');
      } else if (w is EditableText) {
        sb.write('E${w.controller.text}\u0001');
      }
      final kind = w is Scaffold
          ? 'Scaffold'
          : w is Dialog
          ? 'Dialog'
          : w is BottomSheet
          ? 'BottomSheet'
          : null;
      if (kind != null) {
        final route = ModalRoute.of(e);
        if (route != null && seenRoutes.add(identityHashCode(route))) {
          routes.add(_Route(route, e, kind));
        }
      }
      return true;
    });
    return _Snapshot(sb.toString(), routes);
  }

  String? _titleOf(_Route? r) {
    if (r == null) return null;
    String? first;
    String? appBar;
    var n = 0;
    _walk(r.element, (e) {
      final w = e.widget;
      if (w is AppBar && appBar == null) {
        _walk(e, (x) {
          final t = x.widget;
          if (t is Text && appBar == null) {
            appBar = t.data ?? t.textSpan?.toPlainText();
          }
          return true;
        });
      }
      if (w is Text && n < 1) {
        first = w.data ?? w.textSpan?.toPlainText();
        n++;
      }
      return true;
    });
    final t = appBar ?? first;
    if (t == null || t.trim().isEmpty) return null;
    return t.trim().replaceAll('\n', ' ');
  }

  String? _kindOf(Widget w) {
    if (w is ButtonStyleButton) return w.enabled ? 'button' : null;
    if (w is FloatingActionButton) return w.onPressed != null ? 'fab' : null;
    if (w is IconButton) return w.onPressed != null ? 'iconbutton' : null;
    if (w is ListTile) return w.onTap != null && w.enabled ? 'listtile' : null;
    if (w is Switch) return w.onChanged != null ? 'switch' : null;
    if (w is Checkbox) return w.onChanged != null ? 'checkbox' : null;
    if (w is ActionChip) return w.onPressed != null ? 'chip' : null;
    if (w is FilterChip) return w.onSelected != null ? 'chip' : null;
    if (w is ChoiceChip) return w.onSelected != null ? 'chip' : null;
    if (w is InputChip) {
      return (w.onPressed != null || w.onSelected != null) ? 'chip' : null;
    }
    if (w is InkResponse) return w.onTap != null ? 'inkwell' : null;
    if (w is GestureDetector) return w.onTap != null ? 'gesture' : null;
    return null;
  }

  String _labelOf(Element e) {
    final parts = <String>[];
    String? icon;
    String? tip;
    String? sem;
    _walk(e, (x) {
      final w = x.widget;
      if (w is Text && parts.length < 3) {
        final s = (w.data ?? w.textSpan?.toPlainText() ?? '').trim();
        if (s.isNotEmpty) parts.add(s.replaceAll('\n', ' '));
      } else if (w is Icon && icon == null) {
        icon =
            w.semanticLabel ??
            'icon U+${(w.icon?.codePoint ?? 0).toRadixString(16)}';
      } else if (w is Tooltip && tip == null) {
        tip = w.message;
      } else if (w is Semantics && sem == null) {
        sem = w.properties.label;
      }
      return true;
    });
    final w = e.widget;
    if (w is IconButton && w.tooltip != null) tip = w.tooltip;
    if (parts.isNotEmpty) return parts.join(' / ');
    return tip ?? sem ?? icon ?? w.runtimeType.toString();
  }

  List<_Cand> _candidates() {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];
    final view = tester.view;
    final screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final raw = <(Element, String)>[];
    _walk(root, (e) {
      final w = e.widget;
      if (w is ModalBarrier) return false;
      final kind = _kindOf(w);
      if (kind != null) raw.add((e, kind));
      return true;
    });
    final out = <_Cand>[];
    final ordinal = <String, int>{};
    for (final (e, kind) in raw) {
      if (!e.mounted) continue;
      final ro = e.renderObject;
      if (ro is! RenderBox || !ro.attached || !ro.hasSize || ro.size.isEmpty) {
        continue;
      }
      // Shell navigation, the Add button, back/close buttons: driven by the
      // caller or not an action of this screen.
      if (e.findAncestorWidgetOfExactType<NavigationBar>() != null ||
          e.findAncestorWidgetOfExactType<BackButton>() != null ||
          e.findAncestorWidgetOfExactType<CloseButton>() != null ||
          e.findAncestorWidgetOfExactType<ModalBarrier>() != null ||
          e.findAncestorWidgetOfExactType<NavigationRail>() != null) {
        continue;
      }
      if (_isShellAdd(e)) continue;
      final center = ro.localToGlobal(ro.size.center(Offset.zero));
      if (!screen.deflate(2).contains(center)) continue;
      if (out.any((o) => (o.center - center).distance < 6)) continue;
      if (!_hits(center, ro)) continue;
      final label = _labelOf(e);
      if (deny.any((d) => d.isNotEmpty && label.contains(d))) continue;
      if (navLabels.contains(label)) continue;
      // Digits are dropped from the key: counters and clocks change a
      // label between two looks at the same widget.
      final stable = label.replaceAll(
        RegExp(r'[0-9\u0660-\u0669\u06F0-\u06F9]'),
        '#',
      );
      final n = ordinal.update(
        '$kind|$stable',
        (v) => v + 1,
        ifAbsent: () => 0,
      );
      out.add(_Cand(e, kind, label, center, '$kind|$stable|$n'));
    }
    return out;
  }

  bool _isShellAdd(Element e) {
    var found = false;
    e.visitAncestorElements((a) {
      if (a.widget.runtimeType.toString() == 'ZAddButton') {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  bool _hits(Offset at, RenderObject target) {
    final result = HitTestResult();
    final view = tester.view;
    WidgetsBinding.instance.hitTestInView(result, at, view.viewId);
    return result.path.any((h) => identical(h.target, target));
  }

  Future<bool> _scrollDown() async {
    final snap = _snapshot();
    final top = snap.routes.isEmpty ? null : snap.routes.last;
    if (top == null) return false;
    ScrollableState? found;
    _walk(top.element, (e) {
      if (found != null) return false;
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        if (s.axisDirection == AxisDirection.down ||
            s.axisDirection == AxisDirection.up) {
          found = s;
          return false;
        }
      }
      return true;
    });
    final s = found;
    if (s == null || !s.mounted) return false;
    final pos = s.position;
    if (pos.pixels >= pos.maxScrollExtent - 1) return false;
    final before = pos.pixels;
    final box = s.context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    final start = box.localToGlobal(box.size.center(Offset.zero));
    await tester.dragFrom(start, const Offset(0, -380));
    await _settle(minMs: 200);
    return (pos.pixels - before).abs() > 1;
  }

  // ------------------------------------------------------------ report

  String markdown({String? title}) {
    final b = StringBuffer();
    final issues = [for (final s in screens) ...s.issues];
    int count(String k) => issues.where((i) => i.kind == k).length;
    b
      ..writeln('# ${title ?? 'Explorer run'}')
      ..writeln()
      ..writeln(
        'Screens: ${screens.length}. Taps: $_taps. '
        'Issues: ${issues.length} '
        '(exceptions ${count('exception')}, overflows ${count('overflow')}, '
        'dead taps ${count('dead-tap')}, dead ends ${count('dead-end')}, '
        'not reopened ${count('restore')}, '
        'left app ${count('left-app')}).',
      )
      ..writeln();
    if (issues.isNotEmpty) {
      b
        ..writeln('## Issues')
        ..writeln()
        ..writeln('| Screen | Kind | Where | Detail |')
        ..writeln('|---|---|---|---|');
      for (final s in screens) {
        for (final i in s.issues) {
          b.writeln(
            '| ${_c(s.title)} (${s.shot}) | ${i.kind} | ${_c(i.where)} | ${_c(i.detail)} |',
          );
        }
      }
      b.writeln();
    }
    b
      ..writeln('## Screens')
      ..writeln();
    for (final s in screens) {
      b
        ..writeln(
          '### ${s.index}. ${_c(s.title)} (`${s.shot}`, ${s.kind}, depth ${s.depth})',
        )
        ..writeln()
        ..writeln(
          'Tappable: ${s.candidates}. Tapped: ${s.taps.length}'
          '${s.capped ? ' (capped)' : ''}.',
        )
        ..writeln();
      for (final t in s.taps) {
        b.writeln('- ${t.kind} "${_c(t.label)}" -> ${t.outcome}');
      }
      b.writeln();
    }
    return b.toString();
  }

  String _c(String s) => s.replaceAll('|', '/').replaceAll('\n', ' ');

  /// An error that reached the zone (async code in a tap handler) instead of
  /// FlutterError.onError; the test's zone guard hands it here.
  void recordUncaught(Object error) {
    final rec = _cur ?? (screens.isEmpty ? null : screens.last);
    if (rec == null) return;
    final text = error.toString().split('\n').first;
    final line = text.length > 160 ? '${text.substring(0, 160)}...' : text;
    rec.issues.add(ExplorerIssue('exception', _curWhere, 'uncaught: $line'));
    log('EXPLORER_ISSUE exception ${rec.title} / $_curWhere / uncaught: $line');
  }

  /// Stops the run at the next safe point.
  void stop() => _stopped = true;

  int get deadTaps => _dead;
  int get tapCount => _taps;
}

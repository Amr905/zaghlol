// Fixture for no_ui_string_literals: violations inside build methods.
import 'package:flutter/widgets.dart';

class BadView extends StatelessWidget {
  const BadView({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // expect_lint: no_ui_string_literals
        const Text('Hello'),
        // expect_lint: no_ui_string_literals
        Text('Total: $count'),
        // expect_lint: no_ui_string_literals
        const Text('مرحبا يا باشا'),
        Builder(
          // expect_lint: no_ui_string_literals
          builder: (context) => const Text('Inside a closure'),
        ),
      ],
    );
  }
}

/// Widget helpers outside `build` are UI scope too (T-002 review finding 3).
class HelperView extends StatelessWidget {
  const HelperView({super.key});

  @override
  Widget build(BuildContext context) => _header();

  Widget _header() {
    // expect_lint: no_ui_string_literals
    return const Text('Helper text');
  }

  Widget get footer =>
      // expect_lint: no_ui_string_literals
      const Text('Getter text');

  List<Widget> rows() => [
    // expect_lint: no_ui_string_literals
    const Text('Row text'),
  ];
}

Widget topLevelHelper() {
  // expect_lint: no_ui_string_literals
  return const Text('Top level text');
}

/// FU-031: an allowed `name:` argument must not excuse a widget nested in it.
class Slot extends StatelessWidget {
  const Slot({super.key, this.name, this.child});

  final Widget? name;
  final Widget? child;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class NestedInAllowedArgument extends StatelessWidget {
  const NestedInAllowedArgument({super.key});

  @override
  Widget build(BuildContext context) {
    return const Slot(
      key: ValueKey('nested'),
      // expect_lint: no_ui_string_literals
      name: Text('Nested text'),
    );
  }
}

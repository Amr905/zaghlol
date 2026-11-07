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

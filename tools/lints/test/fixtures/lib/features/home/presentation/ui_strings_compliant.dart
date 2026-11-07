// Compliant: allow-listed technical strings, strings outside build methods,
// and text passed in from outside. No lint may fire here.
import 'package:flutter/widgets.dart';

const String kOutsideBuild = 'Constants outside build are not checked';

class GoodView extends StatelessWidget {
  const GoodView({super.key, required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    assert(count >= 0, 'count must not be negative');
    final isHome = label == 'home_tab';
    return Column(
      key: const ValueKey('home_column'),
      children: [
        Text(label),
        const Text(' '),
        const Text('·'),
        const Text('٣٠'),
        Text('$count'),
        Image.asset('assets/images/pigeon.png'),
        Text(label, style: const TextStyle(fontFamily: 'Cairo')),
        Container(key: const Key('panel')),
        if (isHome) const SizedBox.shrink(),
      ],
    );
  }

  String describe() => 'Developer-facing text outside build';
}

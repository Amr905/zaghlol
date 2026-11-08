@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/theme/z_tokens.dart';
import 'package:zaghlol/core/ui/z_components.dart';

import '../support/golden_matrix.dart';

Widget _gap() => const SizedBox(height: ZSpacing.md);

Widget _buttons() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    ZButton(label: 'Save حفظ', onPressed: () {}),
    _gap(),
    ZButton(label: 'Gold', onPressed: () {}, variant: ZButtonVariant.gold),
    _gap(),
    ZButton(
      label: 'Secondary',
      onPressed: () {},
      variant: ZButtonVariant.secondary,
    ),
    _gap(),
    ZButton(label: 'Text', onPressed: () {}, variant: ZButtonVariant.text),
    _gap(),
    ZButton(
      label: 'Delete',
      onPressed: () {},
      variant: ZButtonVariant.destructive,
    ),
    _gap(),
    const ZButton(label: 'Disabled', onPressed: null),
    _gap(),
    ZButton(label: 'Loading', onPressed: () {}, loading: true),
    _gap(),
    ZButton(label: 'Small', onPressed: () {}, size: ZButtonSize.small),
  ],
);

Widget _chips() => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Wrap(
      spacing: ZSpacing.sm,
      runSpacing: ZSpacing.sm,
      children: [
        ZChip(label: 'All الكل', selected: true, onTap: () {}),
        ZChip(label: 'Food', onTap: () {}, icon: Icons.restaurant),
        ZChip(label: 'CIB 1234', selected: true, onClear: () {}),
      ],
    ),
    _gap(),
    const Wrap(
      spacing: ZSpacing.sm,
      runSpacing: ZSpacing.sm,
      children: [
        ZPill(label: 'SMS'),
        ZPill(label: 'Info', tone: ZPillTone.info),
        ZPill(label: 'Paid', tone: ZPillTone.success),
        ZPill(label: 'Review', tone: ZPillTone.warning, icon: Icons.flag),
        ZPill(label: 'Over', tone: ZPillTone.danger),
        ZPill(
          label: 'Gold',
          tone: ZPillTone.gold,
          icon: Icons.workspace_premium,
        ),
      ],
    ),
  ],
);

Widget _cards() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    const ZCard(child: Text('Card كارت')),
    _gap(),
    ZCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          ZListRow(
            title: 'Carrefour كارفور',
            subtitle: 'CIB 1234',
            leading: const ZCategoryTile(
              color: Color(0xFF3E8A86),
              child: Icon(Icons.shopping_basket, size: 20),
            ),
            trailing: const ZMoneyText(text: '-450 EGP'),
            onTap: () {},
          ),
          ZListRow(title: 'Settings', showChevron: true, onTap: () {}),
          const ZListRow(title: 'Disabled', enabled: false),
        ],
      ),
    ),
  ],
);

Widget _money() => const Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    ZMoneyText(text: '-12,400 EGP', size: ZMoneySize.display),
    ZMoneyText(text: '-450 EGP', size: ZMoneySize.title),
    ZMoneyText(text: '+3,500 EGP', kind: ZMoneyKind.income),
    ZMoneyText(text: '450 EGP', kind: ZMoneyKind.neutral),
    ZMoneyText(
      text: '-450 EGP',
      size: ZMoneySize.caption,
      masked: true,
      maskedText: '•••',
    ),
  ],
);

Widget _banners() => Column(
  crossAxisAlignment: CrossAxisAlignment.stretch,
  children: [
    const ZBanner(message: 'Info banner بانر'),
    _gap(),
    ZBanner(
      message: 'Warning banner',
      tone: ZBannerTone.warning,
      actionLabel: 'Fix',
      onAction: () {},
    ),
    _gap(),
    ZBanner(message: 'Error banner', tone: ZBannerTone.error, onDismiss: () {}),
    _gap(),
    const ZBanner(message: 'Success banner', tone: ZBannerTone.success),
  ],
);

Widget _segmented() => ZSegmentedControl<int>(
  segments: const [
    ZSegment(value: 0, label: 'Month شهر'),
    ZSegment(value: 1, label: 'Week'),
    ZSegment(value: 2, label: 'Year'),
  ],
  selected: 1,
  onChanged: (_) {},
);

Widget _sheet() => ZSheetBody(
  title: 'Sheet شيت',
  actions: ZButton(label: 'Done', onPressed: () {}, expand: true),
  child: const Text('Sheet content'),
);

void main() {
  goldenMatrix('buttons', _buttons, size: const Size(390, 560));
  goldenMatrix('chips_pills', _chips, size: const Size(390, 240));
  goldenMatrix('cards_rows', _cards, size: const Size(390, 360));
  goldenMatrix('money_text', _money, size: const Size(390, 240));
  goldenMatrix('banners', _banners, size: const Size(390, 420));
  goldenMatrix('segmented', _segmented, size: const Size(390, 100));
  goldenMatrix('sheet', _sheet, size: const Size(390, 240));

  // Text scale 1.3: every component group must lay out without overflow.
  goldenMatrix(
    'buttons_scaled',
    _buttons,
    variants: goldenVariantsScaled,
    size: const Size(390, 720),
  );
  goldenMatrix(
    'cards_rows_scaled',
    _cards,
    variants: goldenVariantsScaled,
    size: const Size(390, 460),
  );
  goldenMatrix(
    'banners_scaled',
    _banners,
    variants: goldenVariantsScaled,
    size: const Size(390, 560),
  );
}

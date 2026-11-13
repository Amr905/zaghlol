// T-163: S-64 Edit category (Gold). Create or edit a custom category or
// subcategory; delete needs a replacement category (FR-CAT-07). Without
// Gold the screen is read-only (BR-GOLD-04: downgrade keeps categories
// readable, not creatable).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../gold/application/gating.dart';
import '../data/categories_admin.dart';
import 'categories_providers.dart';
import 'category_visuals.dart';

const int maxCategoryNameLength = 30;

/// Bucket codes in display order (matches the label order in the editor).
const List<String> bucketOrder = [
  'needs',
  'wants',
  'obligations',
  'savings',
  'income',
  'giving',
];

class CategoryEditScreen extends ConsumerStatefulWidget {
  const CategoryEditScreen({super.key, this.categoryId, this.parentId});

  /// Null: create.
  final String? categoryId;

  /// Preselected parent when creating a subcategory.
  final String? parentId;

  @override
  ConsumerState<CategoryEditScreen> createState() => _State();
}

class _State extends ConsumerState<CategoryEditScreen> {
  final _name = TextEditingController();
  String? _parent;
  String? _bucket;
  String _icon = categoryIcons.keys.first;
  String _color = categoryPalette.first;
  bool _loaded = false;
  bool _saving = false;
  bool _failed = false;
  bool _bucketMissing = false;

  @override
  void initState() {
    super.initState();
    _parent = widget.parentId;
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _load(List<CategoryItem> all) {
    if (_loaded) return;
    _loaded = true;
    final id = widget.categoryId;
    if (id == null) return;
    for (final c in all) {
      if (c.id == id) {
        _name.text = c.nameEn;
        _parent = c.parentId;
        _bucket = c.bucket;
        _icon = c.icon;
        _color = c.color;
      }
    }
  }

  bool get _nameOk {
    final n = _name.text.trim();
    return n.isNotEmpty && n.length <= maxCategoryNameLength;
  }

  Future<void> _save(bool gold) async {
    if (!gold || _saving) return;
    if (_bucket == null) {
      setState(() => _bucketMissing = true);
      return;
    }
    if (!_nameOk) return;
    setState(() {
      _saving = true;
      _failed = false;
    });
    try {
      final admin = await ref.read(categoriesAdminProvider.future);
      if (widget.categoryId == null) {
        await admin.create(
          name: _name.text,
          bucket: _bucket!,
          icon: _icon,
          color: _color,
          parentId: _parent,
        );
      } else {
        await admin.update(
          widget.categoryId!,
          name: _name.text,
          bucket: _bucket!,
          icon: _icon,
          color: _color,
          parentId: _parent,
        );
      }
      ref.invalidate(categoryItemsProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on Object {
      if (mounted) {
        setState(() {
          _saving = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _delete(CategoryItem self, List<CategoryItem> all) async {
    final t = AppLocalizations.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final choices = [
      for (final c in all)
        if (c.id != self.id && c.parentId != self.id) c,
    ];
    final replacement = await showDialog<String>(
      context: context,
      builder: (ctx) => _DeleteDialog(
        title: t.categoriesEditDeleteTitle(self.name(lang)),
        choices: choices,
        lang: lang,
      ),
    );
    if (replacement == null || !mounted) return;
    try {
      final admin = await ref.read(categoriesAdminProvider.future);
      await admin.deleteWithReplacement(self.id, replacementId: replacement);
      ref.invalidate(categoryItemsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t.categoriesEditDeleted)));
      Navigator.of(context).pop(true);
    } on Object {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final lang = Localizations.localeOf(context).languageCode;
    final gold = ref.watch(entitlementStateProvider).isGold;
    final items = ref.watch(categoryItemsProvider);
    final editing = widget.categoryId != null;

    final labels = [
      t.categoriesEditBucketNeeds,
      t.categoriesEditBucketWants,
      t.categoriesEditBucketObligations,
      t.categoriesEditBucketSavings,
      t.categoriesEditBucketIncome,
      t.categoriesEditBucketGiving,
    ];
    final buckets = {
      for (var i = 0; i < bucketOrder.length; i++) bucketOrder[i]: labels[i],
    };

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: c.text,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: t.commonActionClose,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          editing ? t.categoriesEditTitleEdit : t.categoriesEditTitleNew,
          style: ZType.title.copyWith(color: c.text),
        ),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: ZSpacing.sm),
            child: ZButton(
              label: t.commonActionSave,
              size: ZButtonSize.small,
              loading: _saving,
              onPressed: gold && _nameOk ? () => _save(gold) : null,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: items.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(ZSpacing.xl),
              child: Text(
                t.commonErrorLoadFailed,
                textAlign: TextAlign.center,
                style: ZType.body.copyWith(color: c.text),
              ),
            ),
          ),
          data: (all) {
            _load(all);
            final self = editing
                ? all.where((x) => x.id == widget.categoryId).firstOrNull
                : null;
            final parents = [
              for (final p in all)
                if (p.parentId == null && p.id != widget.categoryId) p,
            ];
            return ListView(
              padding: const EdgeInsetsDirectional.all(ZSpacing.screen),
              children: [
                if (!gold) ...[
                  Container(
                    padding: const EdgeInsetsDirectional.all(ZSpacing.md),
                    decoration: BoxDecoration(
                      color: c.accentLight,
                      borderRadius: BorderRadius.circular(ZRadius.md),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline, color: c.onAccent),
                        const SizedBox(width: ZSpacing.sm),
                        Expanded(
                          child: Text(
                            t.categoriesEditLockedBody,
                            style: ZType.body.copyWith(color: c.onAccent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ZSpacing.md),
                  ZButton(
                    label: t.commonGoldUnlock,
                    variant: ZButtonVariant.gold,
                    expand: true,
                    onPressed: () => ref.read(paywallTriggerProvider)(
                      GoldCapability.customCategories,
                    ),
                  ),
                  const SizedBox(height: ZSpacing.lg),
                ],
                TextField(
                  controller: _name,
                  enabled: gold,
                  maxLength: maxCategoryNameLength,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: t.categoriesEditName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: ZSpacing.md),
                DropdownButtonFormField<String?>(
                  initialValue: parents.any((p) => p.id == _parent)
                      ? _parent
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: t.categoriesEditParent,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(t.categoriesEditParentNone),
                    ),
                    for (final p in parents)
                      DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(p.name(lang)),
                      ),
                  ],
                  onChanged: gold ? (v) => setState(() => _parent = v) : null,
                ),
                const SizedBox(height: ZSpacing.lg),
                Text(
                  t.categoriesEditBucket,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.sm),
                Wrap(
                  spacing: ZSpacing.sm,
                  runSpacing: ZSpacing.sm,
                  children: [
                    for (final e in buckets.entries)
                      ChoiceChip(
                        label: Text(e.value),
                        selected: _bucket == e.key,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        onSelected: gold
                            ? (_) => setState(() {
                                _bucket = e.key;
                                _bucketMissing = false;
                              })
                            : null,
                      ),
                  ],
                ),
                if (_bucketMissing)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                    child: Text(
                      t.categoriesEditBucketRequired,
                      style: ZType.bodySmall.copyWith(color: c.dangerText),
                    ),
                  ),
                const SizedBox(height: ZSpacing.lg),
                Text(
                  t.categoriesEditIcon,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.sm),
                Wrap(
                  spacing: ZSpacing.sm,
                  runSpacing: ZSpacing.sm,
                  children: [
                    for (final e in categoryIcons.entries)
                      _Swatch(
                        selected: _icon == e.key,
                        onTap: gold
                            ? () => setState(() => _icon = e.key)
                            : null,
                        child: Icon(e.value, color: c.text),
                      ),
                  ],
                ),
                const SizedBox(height: ZSpacing.lg),
                Text(
                  t.categoriesEditColor,
                  style: ZType.titleSmall.copyWith(color: c.text),
                ),
                const SizedBox(height: ZSpacing.sm),
                Wrap(
                  spacing: ZSpacing.sm,
                  runSpacing: ZSpacing.sm,
                  children: [
                    for (final hex in categoryPalette)
                      _Swatch(
                        selected: _color == hex,
                        onTap: gold ? () => setState(() => _color = hex) : null,
                        child: CircleAvatar(
                          radius: 12,
                          backgroundColor: parseHexColor(hex),
                        ),
                      ),
                  ],
                ),
                if (_failed)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: ZSpacing.md),
                    child: Text(
                      t.commonErrorSaveFailed,
                      style: ZType.body.copyWith(color: c.dangerText),
                    ),
                  ),
                if (self != null && !self.isSystem) ...[
                  const SizedBox(height: ZSpacing.xl),
                  ZButton(
                    label: t.categoriesEditDelete,
                    variant: ZButtonVariant.destructive,
                    expand: true,
                    onPressed: gold ? () => _delete(self, all) : null,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.selected,
    required this.onTap,
    required this.child,
  });
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ZRadius.md),
        child: Container(
          width: ZSpacing.minTarget,
          height: ZSpacing.minTarget,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZRadius.md),
            border: Border.all(
              color: selected ? c.primary : c.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Asks for the replacement category; confirm stays off until one is chosen.
class _DeleteDialog extends StatefulWidget {
  const _DeleteDialog({
    required this.title,
    required this.choices,
    required this.lang,
  });
  final String title;
  final List<CategoryItem> choices;
  final String lang;

  @override
  State<_DeleteDialog> createState() => _DeleteDialogState();
}

class _DeleteDialogState extends State<_DeleteDialog> {
  String? _pick;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.categoriesEditDeleteBody),
            const SizedBox(height: ZSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _pick,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: t.categoriesEditMoveTo,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final c in widget.choices)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.name(widget.lang)),
                  ),
              ],
              onChanged: (v) => setState(() => _pick = v),
            ),
            if (_pick == null)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: ZSpacing.xs),
                child: Text(
                  t.categoriesEditMoveRequired,
                  style: ZType.bodySmall,
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.commonActionCancel),
        ),
        TextButton(
          onPressed: _pick == null
              ? null
              : () => Navigator.of(context).pop(_pick),
          child: Text(t.categoriesEditDeleteConfirm),
        ),
      ],
    );
  }
}

// T-163: S-63 Categories & rules. System categories (read-only names), the
// user's merchant rules (edit category, delete with Undo) and the entry to
// custom categories, which are Gold (FR-CAT-07/08, BR-GOLD-04). A rule the
// user keeps always beats the catalog; this screen never touches that
// order, it only edits rules through the repository.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/generated/app_localizations.dart';
import '../../../core/theme/z_tokens.dart';
import '../../../core/ui/z_button.dart';
import '../../../core/ui/z_segmented.dart';
import '../../../core/ui/z_sheet.dart';
import '../../gold/application/gating.dart';
import '../../settings/presentation/settings_widgets.dart';
import '../data/categories_admin.dart';
import '../data/rules_providers.dart';
import '../domain/merchant_rule.dart';
import 'categories_providers.dart';
import 'category_edit_screen.dart';
import 'category_visuals.dart';

enum _Tab { categories, rules }

class CategoriesRulesScreen extends ConsumerStatefulWidget {
  const CategoriesRulesScreen({super.key});

  @override
  ConsumerState<CategoriesRulesScreen> createState() => _State();
}

class _State extends ConsumerState<CategoriesRulesScreen> {
  _Tab _tab = _Tab.categories;
  String _query = '';

  Future<void> _newCategory({String? parentId}) async {
    final state = ref.read(entitlementStateProvider);
    final d = GoldGate.check(state, GoldCapability.customCategories);
    if (!d.allowed) {
      ref.read(paywallTriggerProvider)(GoldCapability.customCategories);
      return;
    }
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CategoryEditScreen(parentId: parentId)),
    );
  }

  Future<void> _openCustom(CategoryItem c) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => CategoryEditScreen(categoryId: c.id)),
    );
  }

  Future<void> _showSubs(CategoryItem parent, List<CategoryItem> all) async {
    final lang = Localizations.localeOf(context).languageCode;
    final subs = [
      for (final c in all)
        if (c.parentId == parent.id) c,
    ];
    await showZSheet<void>(
      context: context,
      title: parent.name(lang),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final t = AppLocalizations.of(ctx);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in subs)
                SettingsRow(
                  leading: Icon(iconFor(s.icon)),
                  title: s.name(lang),
                  onTap: s.isSystem
                      ? null
                      : () {
                          Navigator.of(ctx).pop();
                          _openCustom(s);
                        },
                ),
              const SizedBox(height: ZSpacing.sm),
              _NewButton(
                label: t.categoriesListNewSub,
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _newCategory(parentId: parent.id);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editRule(MerchantRule r, List<CategoryItem> all) async {
    final lang = Localizations.localeOf(context).languageCode;
    final picked = await showZSheet<String>(
      context: context,
      title: AppLocalizations.of(context).categoriesListRuleEditA11y,
      fullHeight: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in all)
            SettingsRow(
              leading: Icon(iconFor(c.icon)),
              title: c.name(lang),
              trailing: c.id == r.categoryId ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(ctx).pop(c.id),
            ),
        ],
      ),
    );
    if (picked == null || picked == r.categoryId || !mounted) return;
    final repo = await ref.read(rulesRepositoryProvider.future);
    await repo.changeCategory(r.id, picked);
    ref.invalidate(rulesListProvider);
  }

  Future<void> _deleteRule(MerchantRule r) async {
    final t = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.categoriesListRuleDeleteTitle),
        content: Text(t.categoriesListRuleDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.commonActionCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(t.commonActionDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = await ref.read(rulesRepositoryProvider.future);
    await repo.delete(r.id);
    ref.invalidate(rulesListProvider);
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.hideCurrentSnackBar();
    m.showSnackBar(
      SnackBar(
        content: Text(t.categoriesListRuleDeleted),
        action: SnackBarAction(
          label: t.commonActionUndo,
          onPressed: () async {
            await repo.save(
              kind: r.kind,
              value: r.value,
              categoryId: r.categoryId,
            );
            ref.invalidate(rulesListProvider);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = ZColors.of(context);
    final cats = ref.watch(categoryItemsProvider);

    return SettingsScaffold(
      title: t.categoriesListTitle,
      children: [
        ZSegmentedControl<_Tab>(
          segments: [
            ZSegment(
              value: _Tab.categories,
              label: t.categoriesListTabCategories,
            ),
            ZSegment(value: _Tab.rules, label: t.categoriesListTabRules),
          ],
          selected: _tab,
          onChanged: (v) => setState(() => _tab = v),
        ),
        const SizedBox(height: ZSpacing.lg),
        cats.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(ZSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => _ErrorBlock(
            message: t.commonErrorLoadFailed,
            retry: t.commonActionTryAgain,
            onRetry: () {
              ref.invalidate(categoryItemsProvider);
              ref.invalidate(rulesListProvider);
            },
          ),
          data: (all) => _tab == _Tab.categories
              ? _categories(context, all, c, t)
              : _rules(context, all, c, t),
        ),
      ],
    );
  }

  Widget _categories(
    BuildContext context,
    List<CategoryItem> all,
    ZColors c,
    AppLocalizations t,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final gold = ref.watch(entitlementStateProvider).isGold;
    final top = [
      for (final x in all)
        if (x.parentId == null) x,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.categoriesListSystemNote,
          style: ZType.bodySmall.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: ZSpacing.md),
        SettingsSection(
          children: [
            for (final x in top)
              Builder(
                builder: (_) {
                  final n = all.where((s) => s.parentId == x.id).length;
                  return SettingsRow(
                    leading: Icon(iconFor(x.icon), color: c.text),
                    title: x.name(lang),
                    subtitle: n == 0
                        ? null
                        : t.categoriesListSubCount(
                            n,
                            localDigits(ref, context, '$n'),
                          ),
                    // System rows open their subcategories; custom ones the
                    // editor (read-only once Gold lapses).
                    onTap: x.isSystem
                        ? () => _showSubs(x, all)
                        : () => _openCustom(x),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: ZSpacing.md),
        Semantics(
          button: true,
          label: gold
              ? t.categoriesListNew
              : '${t.categoriesListNew}, ${t.commonGoldBadge}',
          child: ZButton(
            label: t.categoriesListNew,
            icon: Icons.add,
            variant: gold ? ZButtonVariant.secondary : ZButtonVariant.gold,
            expand: true,
            onPressed: () => _newCategory(),
          ),
        ),
        if (!gold)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: ZSpacing.sm),
            child: Text(
              t.categoriesEditLockedBody,
              style: ZType.bodySmall.copyWith(color: c.textMuted),
            ),
          ),
      ],
    );
  }

  Widget _rules(
    BuildContext context,
    List<CategoryItem> all,
    ZColors c,
    AppLocalizations t,
  ) {
    final lang = Localizations.localeOf(context).languageCode;
    final rules = ref.watch(rulesListProvider);
    return rules.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(ZSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _ErrorBlock(
        message: t.commonErrorLoadFailed,
        retry: t.commonActionTryAgain,
        onRetry: () => ref.invalidate(rulesListProvider),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(ZSpacing.xl),
            child: Text(
              t.categoriesListRulesEmpty,
              textAlign: TextAlign.center,
              style: ZType.body.copyWith(color: c.textMuted),
            ),
          );
        }
        final q = _query.trim().toLowerCase();
        final names = {for (final x in all) x.id: x.name(lang)};
        final shown = [
          for (final r in list)
            if (q.isEmpty ||
                r.value.toLowerCase().contains(q) ||
                (names[r.categoryId] ?? '').toLowerCase().contains(q))
              r,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.categoriesListRulesCount(
                list.length,
                localDigits(ref, context, '${list.length}'),
              ),
              style: ZType.titleSmall.copyWith(color: c.text),
            ),
            const SizedBox(height: ZSpacing.sm),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: t.categoriesListRulesSearch,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: ZSpacing.md),
            if (shown.isEmpty)
              Padding(
                padding: const EdgeInsets.all(ZSpacing.xl),
                child: Center(
                  child: Text(
                    t.categoriesListNoResults,
                    style: ZType.body.copyWith(color: c.textMuted),
                  ),
                ),
              )
            else
              SettingsSection(
                children: [
                  for (final r in shown)
                    Semantics(
                      label: t.categoriesListRuleA11y(
                        r.value,
                        names[r.categoryId] ?? '',
                      ),
                      excludeSemantics: true,
                      child: SettingsRow(
                        title: r.value,
                        subtitle: names[r.categoryId],
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: ZSpacing.minTarget,
                                minHeight: ZSpacing.minTarget,
                              ),
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: t.categoriesListRuleEditA11y,
                              onPressed: () => _editRule(r, all),
                            ),
                            IconButton(
                              constraints: const BoxConstraints(
                                minWidth: ZSpacing.minTarget,
                                minHeight: ZSpacing.minTarget,
                              ),
                              icon: const Icon(Icons.delete_outline),
                              tooltip: t.categoriesListRuleDeleteA11y,
                              onPressed: () => _deleteRule(r),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _NewButton extends StatelessWidget {
  const _NewButton({required this.label, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ZButton(
    label: label,
    icon: Icons.add,
    expand: true,
    onPressed: onPressed,
  );
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({
    required this.message,
    required this.retry,
    required this.onRetry,
  });
  final String message;
  final String retry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = ZColors.of(context);
    return Column(
      children: [
        Text(
          message,
          textAlign: TextAlign.center,
          style: ZType.body.copyWith(color: c.text),
        ),
        const SizedBox(height: ZSpacing.md),
        ZButton(
          label: retry,
          variant: ZButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

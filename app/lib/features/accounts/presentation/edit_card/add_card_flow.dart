// T-085: entry points the shell wires to the Money tab callbacks (T-083):
// `onAdd` -> [startAddCard], `onOpenAccount`/hidden rows -> [openEditCard].

import 'package:flutter/material.dart';

import '../../domain/account.dart';
import 'add_card_steps.dart';
import 'card_details_screen.dart';

/// Type -> bank -> details. [onSaved] gets the new account (the shell then
/// opens S-41); [onOpenExisting] handles "This card already exists".
Future<void> startAddCard(
  BuildContext context, {
  void Function(Account account)? onSaved,
  void Function(Account existing)? onOpenExisting,
}) async {
  final kind = await showAddCardTypeSheet(context);
  if (kind == null || !context.mounted) return;
  final bank = await pushBankPicker(context);
  if (bank == null || !context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CardDetailsScreen.create(
        kind: kind,
        institution: bank,
        onSaved: onSaved,
        onOpenExisting: onOpenExisting,
      ),
    ),
  );
}

/// Opens S-43 for an existing account.
Future<void> openEditCard(
  BuildContext context,
  Account account, {
  void Function(Account account)? onSaved,
  void Function(Account account)? onOpenCapture,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => CardDetailsScreen.edit(
      account: account,
      onSaved: onSaved,
      onOpenCapture: onOpenCapture,
    ),
  ),
);

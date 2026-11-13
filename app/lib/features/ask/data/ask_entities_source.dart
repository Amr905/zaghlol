// T-110: the names Ask Zaghlol can recognize, read from the user's own
// database: categories (with the seeded Egyptian aliases), merchants the user
// has spent at, and accounts / cards. Everything stays on the device. The
// lists are capped (untrusted size, FR: never throws on garbage).

import 'package:drift/drift.dart' show Variable;
import 'package:zaghlol_parsing/zaghlol_parsing.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/daos/categories_dao.dart';
import '../../accounts/domain/account.dart';

/// Most merchants offered to the grammar (the most-used first).
const int askMaxMerchants = 500;

Future<AskEntities> loadAskEntities(
  AppDatabase db,
  Future<List<Account>> Function() accounts,
) async {
  final cats = await CategoriesDao(db).active();
  final categories = <AskEntity>[
    for (final c in cats)
      AskEntity(c.id, [c.nameAr, c.nameEn, ...?categoryAliases[c.systemCode]]),
  ];
  final rows = await db
      .customSelect(
        'SELECT merchant_norm AS m, max(merchant_raw) AS raw, count(*) AS n '
        'FROM transactions WHERE deleted_at IS NULL '
        'AND merchant_norm IS NOT NULL GROUP BY merchant_norm '
        'ORDER BY n DESC, m LIMIT ?',
        variables: [Variable.withInt(askMaxMerchants)],
        readsFrom: {db.transactions},
      )
      .get();
  final merchants = <AskEntity>[
    for (final r in rows)
      AskEntity(r.read<String>('m'), [
        r.read<String>('m'),
        ?r.readNullable<String>('raw'),
      ], partial: true),
  ];
  final cards = <AskEntity>[
    for (final a in await accounts())
      AskEntity(a.id, [
        a.label,
        if (a.last4 != null) a.last4!,
        if (a.institutionCode != null) a.institutionCode!,
      ], partial: true),
  ];
  return AskEntities(
    categories: categories,
    merchants: merchants,
    accounts: cards,
  );
}

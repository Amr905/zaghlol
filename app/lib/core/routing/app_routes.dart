// T-024: route locations (docs/02-design/03-navigation.md). Tab roots are
// /home, /insights, /money, /zaghlol; pushed screens live under their tab.

abstract final class AppRoutes {
  static const home = '/home';
  static const insights = '/insights';
  static const money = '/money';
  static const zaghlol = '/zaghlol';

  /// S-14 Review queue, inside the Home tab.
  static const review = '/home/review';

  /// S-11 Transactions list, inside the Home tab.
  static const transactions = '/home/transactions';

  /// S-30 Quick add sheet pushed over the current tab (FAB / Add button).
  static const add = '/add';

  /// Same sheet as a child of Home: the target of the `zaghlol://add` deep
  /// link, so a cold start has the Home tab underneath the sheet.
  static const addOverHome = '/home/add';
}

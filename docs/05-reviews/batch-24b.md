# Review batch-24b: FU-ui-2

Reviewer scope: FU-ui-2 (task/FU-ui-2, one commit e8206153). Tests run: `flutter test --exclude-tags benchmark,golden` on test/features/{voice,accounts,onboarding/presentation,insights/presentation/charts}: 204+ passed in the first folders run, all green.

## FU-ui-2: APPROVED

Findings
- minor, all items verified: `kNoValueDash` is defined in z_money_text.dart (exported via z_components) and used in card_detail.dart:477. The displaced doc comments (z_money_text.dart, scan_plan.dart) now sit on the right declarations. The period chip shows in the loading and error branches of charts_screen.dart:75/83, with a test assertion for the loading branch. The edit sheet shows `•••• last4` in an LTR island under each card (scan_results.dart:299), and the test checks both cards.
- minor, charts_screen_test.dart: the error branch also gets the chip but is not asserted. Follow-up only.
- minor, transaction_detail_screen.dart:654/678 and voice_logger_screen.dart:752 still use a literal '—'. Use `kNoValueDash` there in a later pass.
- minor (CI process, not code), FU-218 scaled variants: 15 golden test files now add 4 x1.3 variants each (home and shell also run per platform), about 70 to 80 new PNGs. None are in the diff, so the `golden` job fails (missing master images) until app-regen (target goldens) runs on the batch branch and the PNGs are committed. The golden job time rises by roughly 1.5x for these files (4 new cases per 4 existing). That is acceptable on a parallel CI job, but the regen must run before the merge.
- minor, PO_DECISIONS.md Part 2: edits are accurate. OQ-04/OQ-18 is marked PARTIAL, FU-044 DONE, and five new asks are added (FU-223, FU-195, FU-212, Apple portal, iOS builds). They match the implementation-status follow-ups I checked (FU-218 text). No Part 1 changes.

Design and a11y glance (voice logger vs 12-voice-logger.png; S-32 scan_confirm_screen.dart)
- No hard-coded user-facing strings found in either screen apart from the '—' placeholder above. The close button, remove button and category pill all use minTarget (48). The row's edit area uses minHeight minTarget. Directional insets and AlignmentDirectional are used, so RTL is safe. The 1.3x variants are the new goldens, so the visual check waits for regen.
- minor, the design mock shows the subtitle "راجعهم وبعدين احفظ" and an Arabic "كاش" account label. The implementation shows no subtitle and a "Cash" account pill in Arabic mode, which looks like an English seeded name (data, not a string) and is worth a copy check. The amount InkWell (voice_logger_screen.dart ~781) has no explicit min height; it relies on the row height.

No blocking findings.

## Fix list

None blocking. Pre-merge process step: run app-regen (goldens) on the batch branch so the new x1.3 PNGs exist before the golden job.

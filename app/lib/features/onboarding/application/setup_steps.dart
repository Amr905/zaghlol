// T-104 (FR-ONB-11): which onboarding steps the user skipped. `setup_progress`
// holds `skip_<step>` when a step was skipped and `done_<step>` once it was
// finished later; a step is "left" while it is skipped and not done.

const List<String> setupStepSlugs = [
  'sms',
  'notifications',
  'cards',
  'shortcuts',
  'app_lock',
];

String skippedSlug(String step) => 'skip_$step';
String doneSlug(String step) => 'done_$step';

/// The steps still to finish, in onboarding order.
List<String> stepsLeft(Set<String> progress) => [
  for (final s in setupStepSlugs)
    if (progress.contains(skippedSlug(s)) && !progress.contains(doneSlug(s))) s,
];

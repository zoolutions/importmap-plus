# Striving for Excellence

The principle: when you find something wrong while doing something else, fix it. The hard part is judgment — when does "fixing it" expand scope, and when does it codify the right shape for the next change? In a fork the question has a second edge: every line changed in an upstream-owned file is conflict surface on the next sync.

## What "in the path" means

The principle applies to wrongness *in the path* of the work you are already doing, not wrongness in a file you'd have to detour to find.

In path:

- You're adding a keyword to `pin_package` and see the sibling `pin_remote_package` re-derives the provenance the caller already computed.
- You're adding a `commands_test.rb` case and the neighbouring case hard-codes a jspm URL that `PROVIDER_HOSTS` already knows how to produce.
- You're fixing a pin-line rewrite and notice the same regex is copied in `Npm` with a subtly different anchor.

Out of path:

- You're fixing `outdated` output and decide to restructure how `Map` caches.
- You're adding a `--from` provider and decide to reformat `packager.rb` to your taste.
- You're fixing a typo in a docs page and rewrite the page's structure.

The test: did the work itself surface the wrongness, or did you go looking for it?

## Don't add new callers of code you know is wrong

If your change would add a caller to a method you've just diagnosed as wrong — a regex that drops `preload:` on rewrite, a path join that doesn't go through `vendored_package_path` — stop. Either fix the underlying thing first and add the caller using the right shape, or escalate. Adding a third caller of a workaround is how the workaround becomes the architecture.

## The fork-cost rule

In an upstream-owned file, "the right shape" includes "the shape that merges". Before fixing sibling wrongness there, ask:

- Is the fix a few additive lines? Do it.
- Would it reorder or rewrite an upstream method? Extract the right shape into a fork-only file and leave the upstream method calling it. `Minifier` and `HttpRetries` are the pattern.
- Is the wrongness upstream's bug, unchanged here? Fix it here **and** open the fix against rails/importmap-rails, so the next sync removes the diff instead of conflicting with it.

## Refactor-depth rule

When a failing test flags one wrong spot, look for siblings of the same shape in the same file — a second `Net::HTTP.get_response` outside `with_retries`, a second place that builds a vendored path by hand. Fixing one and leaving its twin teaches the next reader whichever one they hit first.

## What this is NOT

- Not "expand scope to fix unrelated things." If the task is one bug and the surrounding code is structurally fine, ship the one bug.
- Not "reformat upstream's code." Never.
- Not "spend a week on the perfect abstraction." If the small fix is the right shape, the small fix is excellence.

The litmus test: would a reviewer reading the PR feel the diff tells one story? If the helper fix makes the feature commits cleaner, it belongs. If it's "while I'm here," it's a separate PR. When in doubt, ask.

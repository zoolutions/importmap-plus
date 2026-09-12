---
description: "Measure the request path against main in a worktree before claiming a change is faster or slower. Use when a change touches Map#to_json, preloaded_module_paths, pin_all_from directory expansion, the cache sweeper, or the helpers — the code that runs on every page render."
model: sonnet
argument-hint: "optional: what to focus on (to_json | preloads | digest | sweeper)"
---

# Performance Command

Measure, don't guess. This gem has **no benchmark suite** — what it has is a request path that runs on every page render of every app that uses it, so a regression there is expensive and a "speedup" without numbers is a story.

## What is hot, and what is not

| Path | Runs | Measure? |
|---|---|---|
| `Map#to_json`, `preloaded_module_paths`, `preloaded_module_packages` | every render (cached per `cache_key` until the sweeper clears it) | **yes** |
| `Map#digest` | every response that uses `stale_when_importmap_changes` | **yes** |
| `pin_all_from` expansion (`expand_directories_into`) | on cache miss — first render, and after every file change in development | **yes** |
| `cache_sweeper.execute_if_updated` | a `before_action` on every request in development/test | yes, if you touched it |
| `Packager`, `Npm`, `Minifier`, `Commands` | when a developer types `bin/importmap`; dominated by network | **no** — correctness and clear output matter, not microseconds |

A change confined to the command path needs no measurement. Say so and stop.

## The non-negotiable rule

**Baseline `main` on the same machine, same script, before reporting a delta.** If the change already landed, reconstruct the baseline from a worktree — never compare against a number from another machine or another day.

## Workflow

### 1. Write the script once, in the scratchpad

`test/dummy` is a real Rails app with a realistic map (pins, remote pins, several `pin_all_from` directories, integrity on). Drive it with `bin/rails runner`:

```ruby
# /tmp/importmap-bench.rb
require "benchmark"
map = Rails.application.importmap
resolver = ApplicationController.helpers
n = Integer(ENV.fetch("N", "2000"))

def measure(label, n)
  GC.start; GC.disable
  before = GC.stat(:total_allocated_objects)
  t = Benchmark.realtime { n.times { yield } }
  allocs = (GC.stat(:total_allocated_objects) - before) / n
  GC.enable
  printf "%-28s %8.1f µs/call  %6d objs/call\n", label, t / n * 1_000_000, allocs
end

# clear_cache is private (map.rb), hence send — the cold numbers are the point.
measure("to_json (cached)", n)             { map.to_json(resolver: resolver) }
measure("to_json (cold)", n)               { map.send(:clear_cache); map.to_json(resolver: resolver) }
measure("preloaded_module_paths (cold)", n) { map.send(:clear_cache); map.preloaded_module_paths(resolver: resolver) }
measure("digest (cold)", n)                { map.send(:clear_cache); map.digest(resolver: resolver) }
```

### 2. Baseline `main`

```bash
git worktree add --detach /tmp/importmap-baseline origin/main
(cd /tmp/importmap-baseline && bundle install --quiet && cd test/dummy && bin/rails runner /tmp/importmap-bench.rb) > /tmp/before.txt
```

### 3. Measure the branch

```bash
(cd test/dummy && bin/rails runner /tmp/importmap-bench.rb) > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
git worktree remove --force /tmp/importmap-baseline
```

Run each three times; report the middle run.

### 4. Report honestly

- Give µs/call **and** objects/call. Allocation growth on the cached path means something is escaping the cache.
- **Cached vs cold matters more than the absolute.** Production renders are cached; development renders go cold after every file save. A change that speeds up cold and slows down cached moved the cost to production.
- If the delta is within run-to-run noise (three runs disagree by more than the delta), say "within noise".
- If you only measured after, say so.
- Say which asset pipeline (`ASSETS_PIPELINE`) the numbers are for; the resolver differs.

### 5. Keep it continuous

- [ ] Before/after numbers in the PR body when the request path changed
- [ ] A new cache key or memo has a test proving it invalidates on the right change (`test/importmap_test.rb` has the cache-sweeper cases)

## Focus argument

`$ARGUMENTS` names a path — restrict the script to that measurement. Otherwise run all four.

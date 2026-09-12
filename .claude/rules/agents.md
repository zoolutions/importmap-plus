# Agent Orchestration Rules

## Available agents

| Agent | Purpose | When to use |
|---|---|---|
| Explore | read-only codebase search | finding every caller of a Packager method, every test touching a fixture, every docs page mentioning a command |
| Plan | implementation design | a feature that crosses the CLI, Packager and docs; anything with an upstream-merge cost to weigh |
| general-purpose | multi-step research | reading a CDN's API docs, comparing an upstream release's diff |

## Use them without being asked

1. **A feature request that touches more than one layer** → Plan agent first
2. **"Where is X handled?"** across `lib/`, `test/` and `docs/` → Explore agent, not a chain of Grep calls
3. **An upstream sync** → an Explore agent per conflicted file to summarise both sides before you resolve
4. **A docs update** → an Explore agent to find every page under `docs/app/views/docs/pages/` that describes the changed behaviour

## Parallel execution

Independent explorations launch in one message:

```
Agent 1: how does Packager currently rewrite a pin line (regexes, callers)?
Agent 2: which commands_test.rb cases cover update/pristine output?
Agent 3: which docs pages document `update` and `pristine`?
```

Sequential only when one result feeds the next.

## Model choice

Pass a cheaper model for mechanical work instead of letting a subagent inherit the session model: `haiku` for file discovery and pattern sweeps, `sonnet` for reading and summarising a subsystem. Keep the session model for judgment — designing the pin-line change, resolving a semantic conflict.

## When NOT to use an agent

- A known file path → Read it
- One pattern in one directory → Grep
- A single-file edit
- Running a test

## This repo's specific asks

- The command tests hit live CDNs. Don't spawn agents that each run `bundle exec rake test` in parallel — that is exactly the burst the CI guard exists to prevent. One runner at a time.
- `docs/` is a separate app with its own bundle. An agent verifying docs runs commands from inside `docs/`, not the repo root.

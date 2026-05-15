---
id: AGENT-XXX-NNN
title: ""
created: YYYY-MM-DD
maintainer: ""
service_or_repo: ""
last_reviewed: YYYY-MM-DD
---

# Agent Brief: <agent / service / repo name>

> Read this if you're an AI agent (or a new human) about to touch this service.
> It exists to prevent the same wrong-guess class of errors over and over.

## What this is

<!-- One paragraph: what does this service / repo do? Who uses it? -->

## How to run it locally

<!-- Exact commands. Assume nothing. -->

```bash
...
```

## Interfaces

### Inputs

<!-- HTTP endpoints, webhook payloads, message queues, CLI args, files watched, etc. Be concrete about shapes. -->

### Outputs

<!-- Where does data go? Side effects? -->

### Dependencies (services this calls)

- <service name> — <what we call it for, what happens on failure>

### Dependents (services that call this)

- <service name> — <what they expect from us>

## State

<!-- What persistent state does this own? DB tables, files, queues, caches. -->

## Failure modes

<!-- Known ways this breaks. What logs / metrics surface each one. -->

| Symptom | Likely cause | Where to look |
|---|---|---|
| ... | ... | ... |

## Gotchas

<!-- Things that have bitten us before. Subtle invariants. Why-not-the-obvious-approach notes. -->

## Conventions specific to this service

<!-- File layout, naming, where to add new X. -->

## See also

<!-- Links to specs, ADRs, deeper repo docs. -->

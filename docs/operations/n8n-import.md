---
title: Bugsy n8n Workflow Import
tags: [bugsy, n8n, workflows, import, deploy, ops]
---

# n8n workflow import

The n8n DB is the source of truth for what's running. The repo's JSON files are the source of truth for what's *intended* to run. Keep them in sync.

## The flow

1. Claude (or you) edits a JSON file in `agent/n8n/workflows/`
2. Commits and pushes
3. You import the raw GitHub URL into n8n
4. As you tweak in the n8n UI, you export back (`⋮ → Download`) and commit so the repo catches up

Raw URL pattern:
```
https://raw.githubusercontent.com/anthonycoffey/_agent/main/agent/n8n/workflows/<file>.json
```

## Rules to avoid pain

- **Open the existing workflow first, then import.** Importing from URL into a *blank* new workflow creates a duplicate. Importing into the open workflow overwrites in place.
- **Always click Save after import.** Import alone doesn't persist; you need Save (Ctrl+S).
- **Watch for webhook path collisions.** If you import a workflow whose webhook path is already claimed by another active workflow, n8n refuses to activate. Deactivate the conflicting one first.
- **Credential references are by ID.** When importing a JSON that references credentials, the credential IDs must already exist in your n8n instance. If they don't, open the relevant node and re-pick the credential from the dropdown.

## Verifying an import took

In n8n's Postgres:

```bash
docker exec agent-postgres psql -U $POSTGRES_USER -d n8n -c \
  "select name, active, to_char(\"updatedAt\", 'YYYY-MM-DD HH24:MI:SS') as updated, json_array_length(nodes) as nodes from workflow_entity order by \"updatedAt\" desc;"
```

`updatedAt` should be within seconds of when you imported. `nodes` count tells you whether you have the version you expect.

## Authoring rules

n8n's workflow JSON format is undocumented and changes between versions. Don't invent node shapes from training data. Copy node shapes from existing committed workflows in `agent/n8n/workflows/`. If a node type doesn't exist in any committed workflow yet, add it once in the UI, export, share — then it can be reused.

## Keep the docs in sync

Every workflow has an accompanying page under `docs/workflows/` with two parts:

1. **Hand-written summary** — what the workflow does and why.
2. **`## Node reference` block** — auto-generated from the JSON, delimited by `<!-- NODE-REF:START:<basename> -->...<!-- NODE-REF:END:<basename> -->` markers.

After any workflow JSON change, regenerate the reference blocks so the docs stay accurate:

```bash
node agent/n8n/scripts/generate-workflow-reference.mjs
```

The generator only touches content between the markers — narrative text outside them is preserved. Doc ownership is declared via frontmatter `n8n_workflows: [<basename>]`; workflows not yet claimed by a doc get a stub auto-created at `docs/workflows/<basename>.md`. Add a new entry to the `nav:` block in `mkdocs.yml` if the generator creates a new doc.

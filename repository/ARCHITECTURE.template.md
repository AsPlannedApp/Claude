<!--
  TEMPLATE: ARCHITECTURE.md for a single repo in a multi-repo project.
  This is the agent-facing structural contract: where things go, how layers talk to each other,
  and the hard rules an agent must follow when writing new code here. It should be read BEFORE
  writing any new code in the repo (CLAUDE.md should say so explicitly).

  Fill every {{PLACEHOLDER}} from the REAL codebase — the folder tree, the layering table, and
  especially the code-pattern examples must reflect actual files, not invented ones. Delete any
  `OPTIONAL` block that doesn't apply. Delete all HTML comments (including this one) from
  the final output.
-->

# Architecture — {{REPO_NAME}}

{{ONE_LINE_DESCRIPTION_WITH_DEPLOY_TARGET}}

---

## Folder structure

<!-- Walk the real top-level source folders (depth 2-3 is usually enough) and annotate each with
     a short inline comment explaining its purpose — not just its name. Prefer showing 1-2 real
     example filenames per folder over a bare directory name, the way a dev would explain it to
     a new teammate. -->
```
{{FOLDER_TREE}}
```

---

## Responsibility rules

<!-- One row per layer/folder that has a clear single responsibility. This table is the thing an
     agent checks before deciding where a new piece of code belongs — keep it unambiguous. -->
| Layer | Rule |
|---|---|
| **{{LAYER_1}}** | {{LAYER_1_RULE}} |
| **{{LAYER_2}}** | {{LAYER_2_RULE}} |
| **{{LAYER_3}}** | {{LAYER_3_RULE}} |

---

## {{CANONICAL_PATTERN_HEADING}}

<!-- Show the ONE canonical request/data-flow pattern this repo follows end-to-end, with a real
     (or lightly trimmed real) code example — e.g. Controller→Action→Resource→Response for a
     Laravel API, or View→Composable→Service for a Vue SPA, or Route handler→helper→response for
     a Next.js API. Show both a ✅ correct and a ❌ wrong version if the repo has an established
     anti-pattern worth calling out explicitly (this is the highest-value teaching tool in the
     whole file — don't skip it). -->

```{{LANGUAGE}}
// ✅ Correct
{{CORRECT_PATTERN_EXAMPLE}}

// ❌ Wrong
{{WRONG_PATTERN_EXAMPLE}}
```

{{PATTERN_FLOW_SUMMARY}} <!-- e.g. "Flow: FormRequest (validate) → Action (execute) → Resource (format) → ApiResponse (envelope)" -->

---

<!-- OPTIONAL: include if there's a second reusable pattern worth codifying (e.g. a Repository
     pattern, a Service pattern, a composable pattern) — same shape as above, shorter. Repeat as
     a "## {{PATTERN_2_HEADING}}" section per additional pattern. Delete if one pattern covers it. -->

---

<!-- OPTIONAL: only if this repo holds meaningful runtime/UI state outside of what's obvious from
     the framework defaults (e.g. no Pinia/Redux — state lives in a root component's provide()).
     Delete for a stateless API repo. -->
## State management

{{STATE_MANAGEMENT_APPROACH}}

| Key | Type | Purpose |
|---|---|---|
| {{STATE_KEY_1}} | {{STATE_KEY_1_TYPE}} | {{STATE_KEY_1_PURPOSE}} |

---

<!-- OPTIONAL: frontend-only. Delete for backend/API repos. -->
## Design conventions

- **Icons**: {{ICON_LIBRARY_RULE}}
- **Shared components**: {{SHARED_COMPONENT_PACKAGE_RULE}}
- **Colors/tokens**: {{DESIGN_TOKEN_RULE}}

---

## Quality commands

<!-- Same commands as CLAUDE.md's Quality checks section, but this is the canonical source —
     CLAUDE.md may summarize/link back here instead of repeating in full. -->
```bash
{{QUALITY_GATE_COMMAND}}
{{QUALITY_SUBCOMMAND_1}}
{{QUALITY_SUBCOMMAND_2}}
```

<!-- OPTIONAL: if this repo enforces a static-analysis baseline (PHPStan level, ESLint rule
     budget, etc.), state the exact bar so an agent knows what "regression" means. -->
{{STATIC_ANALYSIS_BASELINE}}

---

## Agent rules

<!--
  This is the enforceable core of the file. Write these as short, imperative, checkable
  sentences — each one should be something an agent can be caught violating, not a vibe.
  Good categories to draw from (keep only what applies, in this rough priority order):
    1. The one non-negotiable delegation/layering rule (e.g. "controllers must not contain
       business logic — delegate to an Action").
    2. A testing requirement tied to a concrete artifact type (e.g. "write a feature test for
       every new endpoint before implementing it").
    3. File-type/naming rules (e.g. "new API routes must be .ts, not .js").
    4. A rule about when NOT to introduce a new abstraction (repository/service/composable) —
       prevents premature abstraction as much as under-abstraction.
    5. "Run {{QUALITY_GATE_COMMAND}} after every step — it must pass / must not regress before
       moving on." — almost always belongs here verbatim.
    6. Anything the codebase got wrong before and fixed once, that's cheap to re-break (a real
       gotcha, not a hypothetical one).
    7. A commit-message or diff-hygiene rule if the repo cares about that (e.g. "don't mix
       formatting changes with structural changes in the same commit").
  Number them; keep each to one sentence.
-->

1. {{AGENT_RULE_1}}
2. {{AGENT_RULE_2}}
3. {{AGENT_RULE_3}}
4. {{AGENT_RULE_4}}
5. Run `{{QUALITY_GATE_COMMAND}}` after every step — it must pass before moving on.

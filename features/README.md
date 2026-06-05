# features/

This directory holds **opt-in feature definitions** for the llm-wiki-memory
template. Each subdirectory `features/<name>/` is a self-contained feature
that derived projects can choose to enable, independently of the base
template.

## Status

Etapa 1 of the feature-flag architecture (RFC #13) ships an empty
`features/` directory plus the install/uninstall infrastructure. No real
features ship here yet. The first migration target is the Socratic tutor
(#7) or the future agent-memory tooling, neither of which lands in this
PR.

## Structure of a feature

```
features/<name>/
├── feature.json          # metadata (name, files, tests, ci, claude_md, system_deps, depends_on)
├── CLAUDE.section.md     # prose inserted into the derived project's CLAUDE.md
├── code/                 # files copied into scripts/<name>/ at install time
├── tests/                # files copied into scripts/test-mvp/tests/<category>/<name>/
├── fixtures/             # test data referenced by the feature's own tests
└── ci/
    └── test-<name>.yml   # GitHub Actions workflow copied into .github/workflows/
```

## The two entry points

A derived project enables a feature in one of two ways:

```bash
# At instantiation (declarative)
./scripts/instantiate.sh "Project Name" --agent=claude-code --features=<name>

# Retroactively (procedural)
./scripts/enable-feature.sh <name>
```

Both call `install_feature` in `scripts/lib/install-feature.sh`.

Symmetric removal:

```bash
./scripts/disable-feature.sh <name>
```

## Tracking which features are enabled

A derived project records its enabled features in a `.features-enabled`
file at the project root, one feature name per line. The format is plain
text for now; future metadata (install date, version pinning) can be added
without breaking compatibility.

## Adding a new feature

Drop a new directory under `features/`, write a `feature.json`, and the
existing `install_feature` machinery handles the rest. No changes to
`instantiate.sh` or the install logic are needed per feature.

A proper `docs/adding-a-feature.md` ships in Etapa 5; until then this
README is the rough guide.

## Out of scope for Etapa 1

- KG migration into `features/kg/` (Etapa 2 was skipped per RFC #13 discussion)
- `update-from-template.sh` feature-awareness (Etapa 3)
- `migrate-to-feature-flags.sh` for legacy derived projects (Etapa 4)
- Long-form contributor documentation (Etapa 5)

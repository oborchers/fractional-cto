# fractional-cto

Your AI CTO co-pilot -- opinionated, research-backed Claude Code plugins for building SaaS products that ship.

## How it works

Every plugin activates the moment your Claude session starts. A session hook fires, reads the plugin's skill index, and injects it into context. From that point on, Claude *knows* what principles exist and when to apply them -- no slash commands needed, no manual invocation.

When you're writing an API endpoint, the API design skills kick in. When you're laying out a cloud account structure, the infrastructure principles surface. When you're building a form, the SaaS design rules show up. Each plugin carries review checklists, good/bad pattern comparisons, working code examples, and a dedicated reviewer agent for deeper audits.

The skills are deliberately opinionated. They don't present five options and ask you to choose. They tell you what to do, cite why, and show you the code. If you disagree, edit the skill -- it's just markdown.

## About

Built by [Dr. Oliver Borchers](https://linkedin.com/in/oliverborchers) -- AI engineering lead by day, former startup CTO, open-source tinkerer ([fse](https://github.com/oborchers/Fast_Sentence_Embeddings)). I got tired of giving the same design reviews and architecture feedback across projects, so I turned them into Claude Code skills that kick in automatically.

## What's Inside

### Design

- **[saas-design-principles](./saas-design-principles)** (12 skills) - Speed, navigation, forms, tables, auth, accessibility, theming, responsive design, and more -- drawn from Linear, Stripe, Shopify Polaris, and Nielsen Norman Group research
- **[visual-design-principles](./visual-design-principles)** (11 skills) - Layout, typography, color theory, whitespace, accessibility, and more -- grounded in VisAWI, Gestalt psychology, and empirical aesthetics research
- **[api-design-principles](./api-design-principles)** (12 skills) - Routes, errors, auth, pagination, caching, webhooks, versioning, and more -- drawn from Stripe, GitHub, Twilio, Google, OWASP, and industry RFCs

### Infrastructure

- **[cloud-foundation-principles](./cloud-foundation-principles)** (15 skills) - Multi-account governance, naming conventions, IaC organization, networking, security, deployment pipelines, operational hygiene -- cloud-agnostic with provider-specific translation tables

### Code Quality

- **[pedantic-coder](./pedantic-coder)** (15 skills) - Zero-tolerance code pedantry -- naming precision, casing law, structural symmetry, import discipline, CLAUDE.md guidelines compliance, plus language packs for Python, TypeScript, and Go
- **[python-package](./python-package)** (11 skills) - Modern Python packaging -- project structure, pyproject.toml, Ruff/mypy, pytest, CI/CD, MkDocs, versioning, API design, wheels, supply chain security, developer experience

### Research

- **[deep-research](./deep-research)** (4 skills) - Structured deep research methodology -- query decomposition, parallel web research with source verification, hallucination prevention, and synthesis into well-sourced documents. Three-stage pipeline: research-workers (Sonnet) produce findings with Verifiable Claims Tables, research-verifiers (Sonnet) independently fact-check, research-synthesizer (Opus) merges with corrections and Confidence Assessment

### Thinking & Writing

- **[structured-brainstorming](./structured-brainstorming)** (1 skill) - 8 thinking methods that counteract LLM reasoning biases -- first principles, inversion, constraint manipulation, perspective forcing, analogy search, MECE, assumption surfacing, and diverge-then-converge -- with parallel subagent exploration for deep dives
- **[retell](./retell)** (2 skills) - Transform Claude Code conversations into polished, first-person blog posts -- 5-stage interactive pipeline (parse, triage, outline, draft, polish) with human editorial gates at every stage

Each principle plugin ships with review checklists, working code examples, a review command, a reviewer agent, and a session hook. Deep Research is a multi-agent research pipeline with `/research` command, parallel workers, verifiers, and an Opus synthesizer. Retell is a workflow plugin with a `/retell` command, Sonnet subagents, and Python scripts for conversation parsing.

## Installation

Register the marketplace once:

```bash
/plugin marketplace add oborchers/fractional-cto
```

Then install any plugin:

```bash
/plugin install saas-design-principles@fractional-cto
/plugin install api-design-principles@fractional-cto
/plugin install pedantic-coder@fractional-cto
/plugin install python-package@fractional-cto
/plugin install cloud-foundation-principles@fractional-cto
/plugin install visual-design-principles@fractional-cto
/plugin install structured-brainstorming@fractional-cto
/plugin install retell@fractional-cto
/plugin install deep-research@fractional-cto
```

### Local Development

Test a plugin directly:

```bash
claude --plugin-dir /path/to/fractional-cto/<plugin-name>
```

## Contributing

Plugins live directly in this repository. Each one is a self-contained directory with a `.claude-plugin/plugin.json` manifest. To add a new plugin, create the directory, add skills with review checklists and examples, wire up the session hook, and register it in `.claude-plugin/marketplace.json`.

## License

MIT

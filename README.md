# vibe-cto

Your AI CTO co-pilot -- opinionated, research-backed Claude Code plugins for building SaaS products that ship.

## About

Built by [Dr. Oliver Borchers](https://linkedin.com/in/oliverborchers) -- AI engineering lead by day, former startup CTO, open-source tinkerer ([fse](https://github.com/oborchers/Fast_Sentence_Embeddings)). I got tired of giving the same design reviews and architecture feedback across projects, so I turned them into Claude Code skills that kick in automatically.

## Plugins

| Plugin | Skills | Description |
|--------|--------|-------------|
| **[saas-design-principles](./saas-design-principles)** | 12 | Speed, navigation, forms, tables, auth, accessibility, theming, responsive design, and more -- drawn from Linear, Stripe, Shopify Polaris, and Nielsen Norman Group research |
| **[api-design-principles](./api-design-principles)** | 12 | Routes, errors, auth, pagination, caching, webhooks, versioning, and more -- drawn from Stripe, GitHub, Twilio, Google, OWASP, and industry RFCs |

Each plugin includes principle skills with review checklists, working code examples, a `/review` command, a reviewer agent, and a session hook that loads the skill index on startup.

## Installation

### Claude Code

Register the marketplace once:

```bash
/plugin marketplace add oborchers/vibe-cto
```

Then install any plugin:

```bash
/plugin install saas-design-principles@vibe-cto
/plugin install api-design-principles@vibe-cto
```

### Local Development

Test a specific plugin directly:

```bash
claude --plugin-dir /path/to/vibe-cto/saas-design-principles
claude --plugin-dir /path/to/vibe-cto/api-design-principles
```

## Adding Future Plugins

New plugins go in their own subdirectory with a `.claude-plugin/plugin.json` manifest. Register them in `.claude-plugin/marketplace.json` by adding an entry to the `plugins` array.

## License

MIT

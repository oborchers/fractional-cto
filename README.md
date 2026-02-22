# vibe-cto

Your AI CTO co-pilot -- opinionated, research-backed Claude Code plugins for building SaaS products that ship.

## Plugins

| Plugin | Description |
|--------|-------------|
| **[saas-design-principles](./saas-design-principles)** | The holy principles of SaaS design: 12 research-backed principles covering speed, navigation, forms, tables, auth, accessibility, theming, and more |

## Installation

### Claude Code

Register the marketplace once:

```bash
/plugin marketplace add oborchers/vibe-cto
```

Then install any plugin:

```bash
/plugin install saas-design-principles@vibe-cto
```

### Local Development

Test a specific plugin directly:

```bash
claude --plugin-dir /path/to/vibe-cto/saas-design-principles
```

## Adding Future Plugins

New plugins go in their own subdirectory with a `.claude-plugin/plugin.json` manifest. Register them in `.claude-plugin/marketplace.json` by adding an entry to the `plugins` array.

## License

MIT

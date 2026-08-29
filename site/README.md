# Clipy Secure website

The public website is a static Astro project deployed to GitHub Pages at the
`/clipy-secure/` project path.

## Local development

From this directory:

```bash
npm ci
npm run dev
```

Before submitting a change:

```bash
npm run validate
npm run check
npm run build
```

`npm run validate` checks public content for the product-name typo and
disallowed tool attribution. The GitHub workflow separately applies the same
attribution policy to commits introduced by a pull request or direct push.

## Screenshots

Clean application captures live under `src/images/screenshots/`. The page uses
the clipboard menu and Privacy preferences captures as its two document figures;
the other preference-tab captures are retained for future swaps.

| Screenshot | Source size |
| --- | --- |
| Clipboard menu | 493 × 484 |
| General preferences | 690 × 711 |
| Menu preferences | 656 × 701 |
| Types preferences | 655 × 694 |
| Shortcuts preferences | 653 × 703 |
| Privacy preferences | 668 × 706 |

Keep screenshots free of real URLs, names, sensitive clipboard contents,
notifications, desktop details, and sensitive image metadata. Display captures
with a one-pixel document border and descriptive alternative text.

## Deployment

Pull requests targeting `develop` or `main` validate and build the site. Pushes
to `main` deploy the generated `dist/` artifact through GitHub Pages. Generated
files and installed dependencies remain untracked.

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

## Screenshot handoff

The page uses quiet typographic placeholders until final screenshots are available.
Provide clean PNG source files with these compositions:

| Screenshot | Source size | Content |
| --- | --- | --- |
| Clipboard menu | 1600 × 1000 | Safe fictional clipboard history |
| Search or preferences | 1600 × 1000 | Search, shortcuts, privacy, or excluded-app preferences |

Use Retina captures with consistent macOS appearance. Do not include real URLs,
names, clipboard contents, notifications, desktop details, or sensitive image
metadata.

Once the captures are ready, place their source files under `src/images/` and
replace the matching placeholders in `src/pages/index.astro` with Astro image
components. Keep the one-pixel document border and write descriptive alternative
text for each image.

## Deployment

Pull requests targeting `develop` or `main` validate and build the site. Pushes
to `main` deploy the generated `dist/` artifact through GitHub Pages. Generated
files and installed dependencies remain untracked.

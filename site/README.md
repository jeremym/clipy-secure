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

The initial page uses CSS mockups until final screenshots are available.
Provide clean PNG source files with these compositions:

| Screenshot | Source size | Content |
| --- | --- | --- |
| Clipboard menu | 1600 × 1000 | Safe fictional clipboard history |
| Search workflow | 1600 × 1000 | Search results using fictional content |
| Privacy controls | 1440 × 1080 | Privacy or excluded-app preferences |

Use Retina captures with consistent macOS appearance and generous padding
around the app window. Do not include real URLs, names, clipboard contents,
notifications, desktop details, or sensitive image metadata.

Once the captures are ready, place their source files under `src/images/` and
replace the matching mockups in `Hero.astro` and `ScreenshotShowcase.astro` with
Astro image components.

## Deployment

Pull requests targeting `develop` or `main` validate and build the site. Pushes
to `main` deploy the generated `dist/` artifact through GitHub Pages. Generated
files and installed dependencies remain untracked.

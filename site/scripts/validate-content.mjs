import { execFileSync } from "node:child_process";
import { lstatSync, readFileSync } from "node:fs";
import { dirname, extname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const repositoryRoot = resolve(scriptDirectory, "../..");

const textExtensions = new Set([
  ".astro",
  ".cjs",
  ".css",
  ".entitlements",
  ".html",
  ".js",
  ".json",
  ".jsx",
  ".md",
  ".mdx",
  ".mjs",
  ".pbxproj",
  ".plist",
  ".scss",
  ".sh",
  ".strings",
  ".swift",
  ".svg",
  ".text",
  ".toml",
  ".ts",
  ".tsx",
  ".txt",
  ".xcprivacy",
  ".xcstrings",
  ".xml",
  ".yaml",
  ".yml",
]);

const extensionlessTextFiles = new Set([
  ".gitignore",
  ".swiftformat",
  "CNAME",
  "CODE_OF_CONDUCT",
  "CONTRIBUTING",
  "LICENSE",
  "Makefile",
  "README",
  "SECURITY",
]);

const ignoredPathSegments = new Set([
  ".astro",
  ".context",
  ".git",
  "DerivedData",
  "build",
  "coverage",
  "dist",
  "node_modules",
]);

const ignoredFiles = new Set([
  "package-lock.json",
  "site/scripts/validate-commits.mjs",
  "site/scripts/validate-content.mjs",
]);

const toolName = String.raw`(?:Codex|Claude(?:\s+Code)?|ChatGPT|GitHub\s+Copilot|Copilot|Cursor|Windsurf|Gemini(?:\s+CLI)?|OpenAI)`;
const attributionName = String.raw`(?:AI|artificial\s+intelligence|${toolName})`;
const rules = [
  {
    description: 'Use the product spelling "Clipy", with one p.',
    expression: /\bclippy\b/giu,
  },
  {
    description: "Remove AI-tool attribution from public content.",
    expression: new RegExp(
      String.raw`\b(?:coded|created|generated|written|built|made|developed|powered)\s+(?:by|with|using)\s+(?:an?\s+)?(?:\[)?${attributionName}\b`,
      "giu",
    ),
  },
  {
    description: "Remove AI-tool attribution from public content.",
    expression: /\bAI[-\s]+(?:assisted|generated|coded|written|built|developed)\b/giu,
  },
  {
    description: "Remove coding-agent co-author trailers.",
    expression: new RegExp(
      String.raw`\bco-authored-by\s*:\s*${attributionName}\b`,
      "giu",
    ),
  },
];

function listCandidateFiles() {
  const output = execFileSync(
    "git",
    ["ls-files", "--cached", "--others", "--exclude-standard", "-z"],
    { cwd: repositoryRoot, encoding: "utf8" },
  );

  return output
    .split("\0")
    .filter(Boolean)
    .filter((path) => !ignoredFiles.has(path))
    .filter((path) => !path.split("/").some((segment) => ignoredPathSegments.has(segment)))
    .filter((path) => {
      const name = path.split("/").at(-1);
      return textExtensions.has(extname(name).toLowerCase()) || extensionlessTextFiles.has(name);
    })
    .sort();
}

function locationAt(content, offset) {
  const beforeMatch = content.slice(0, offset);
  const lines = beforeMatch.split("\n");
  return { line: lines.length, column: lines.at(-1).length + 1 };
}

function escapeWorkflowProperty(value) {
  return value.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A").replaceAll(",", "%2C");
}

function escapeWorkflowMessage(value) {
  return value.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");
}

const violations = [];

for (const relativePath of listCandidateFiles()) {
  const absolutePath = resolve(repositoryRoot, relativePath);
  const fileInfo = lstatSync(absolutePath);
  if (!fileInfo.isFile() || fileInfo.isSymbolicLink()) continue;

  const content = readFileSync(absolutePath, "utf8");
  if (content.includes("\0")) continue;

  for (const rule of rules) {
    rule.expression.lastIndex = 0;
    for (const match of content.matchAll(rule.expression)) {
      const { line, column } = locationAt(content, match.index);
      violations.push({ relativePath, line, column, description: rule.description });
    }
  }
}

if (violations.length > 0) {
  console.error(`Public-content validation found ${violations.length} violation${violations.length === 1 ? "" : "s"}:`);
  for (const violation of violations) {
    const location = `${violation.relativePath}:${violation.line}:${violation.column}`;
    console.error(`${location} - ${violation.description}`);
    if (process.env.GITHUB_ACTIONS === "true") {
      console.error(
        `::error file=${escapeWorkflowProperty(violation.relativePath)},line=${violation.line},col=${violation.column}::${escapeWorkflowMessage(violation.description)}`,
      );
    }
  }
  process.exit(1);
}

console.log("Public-content validation passed.");

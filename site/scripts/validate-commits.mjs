import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const scriptPath = fileURLToPath(import.meta.url);
const repositoryRoot = resolve(scriptDirectory, "../..");
const shaPattern = /^(?!0+$)[0-9a-f]{40,64}$/iu;

const toolName = String.raw`(?:Codex|Claude(?:\s+Code)?|ChatGPT|GitHub\s+Copilot|Copilot|Cursor|Windsurf|Gemini(?:\s+CLI)?|OpenAI)`;
const attributionName = String.raw`(?:AI|artificial\s+intelligence|${toolName})`;
const rules = [
  {
    description: "Remove AI-tool attribution from the commit message.",
    expression: new RegExp(
      String.raw`\b(?:coded|created|generated|written|built|made|developed|powered)\s+(?:by|with|using)\s+(?:an?\s+)?(?:\[)?${attributionName}\b`,
      "giu",
    ),
  },
  {
    description: "Remove AI-tool attribution from the commit message.",
    expression: /\bAI[-\s]+(?:assisted|generated|coded|written|built|developed)\b/giu,
  },
  {
    description: "Remove the coding-agent co-author trailer from the commit message.",
    expression: new RegExp(
      String.raw`\bco-authored-by\s*:\s*${attributionName}\b`,
      "giu",
    ),
  },
];

export function findCommitMessageViolations(message) {
  return rules
    .filter((rule) => {
      rule.expression.lastIndex = 0;
      return rule.expression.test(message);
    })
    .map((rule) => rule.description);
}

function assertCommitExists(sha, label) {
  try {
    execFileSync("git", ["cat-file", "-e", `${sha}^{commit}`], {
      cwd: repositoryRoot,
      stdio: "ignore",
    });
  } catch {
    throw new Error(`${label} commit ${sha} is not available. The validator will not fall back to scanning unrelated history.`);
  }
}

function listIntroducedCommits(baseSha, headSha) {
  const output = execFileSync(
    "git",
    ["rev-list", "--reverse", `${baseSha}..${headSha}`],
    { cwd: repositoryRoot, encoding: "utf8" },
  );
  return output.split("\n").filter(Boolean);
}

function readCommitMessage(sha) {
  return execFileSync("git", ["show", "--no-patch", "--format=%B", sha], {
    cwd: repositoryRoot,
    encoding: "utf8",
  });
}

function escapeWorkflowMessage(value) {
  return value.replaceAll("%", "%25").replaceAll("\r", "%0D").replaceAll("\n", "%0A");
}

function main() {
  const [baseSha, headSha, ...unexpectedArguments] = process.argv.slice(2);
  if (unexpectedArguments.length > 0 || !shaPattern.test(baseSha ?? "") || !shaPattern.test(headSha ?? "")) {
    console.error("Usage: node scripts/validate-commits.mjs <non-zero-base-sha> <non-zero-head-sha>");
    process.exit(2);
  }

  try {
    assertCommitExists(baseSha, "Base");
    assertCommitExists(headSha, "Head");
  } catch (error) {
    console.error(error.message);
    process.exit(2);
  }

  const violations = [];
  for (const sha of listIntroducedCommits(baseSha, headSha)) {
    for (const description of findCommitMessageViolations(readCommitMessage(sha))) {
      violations.push({ sha, description });
    }
  }

  if (violations.length > 0) {
    console.error(`Commit-message validation found ${violations.length} violation${violations.length === 1 ? "" : "s"}:`);
    for (const violation of violations) {
      console.error(`${violation.sha} - ${violation.description}`);
      if (process.env.GITHUB_ACTIONS === "true") {
        console.error(
          `::error title=Disallowed commit attribution::${escapeWorkflowMessage(`${violation.sha} - ${violation.description}`)}`,
        );
      }
    }
    process.exit(1);
  }

  console.log("Introduced commit-message validation passed.");
}

if (process.argv[1] && resolve(process.argv[1]) === scriptPath) {
  main();
}

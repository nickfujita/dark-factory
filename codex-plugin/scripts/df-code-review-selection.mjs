#!/usr/bin/env node
/**
 * Code-review input preparation for an immutable verification selection.
 *
 * This is deliberately a thin consumer of df-selection.mjs. It does not know
 * where selections live, how they are canonicalized, or how their source
 * digests are checked. The B1 reader owns those decisions.
 */
import { mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { dirname, isAbsolute, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const SELECTION_HELPER = resolve(SCRIPT_DIR, "df-selection.mjs");

class ReviewSelectionError extends Error {}

function fail(message) {
  throw new ReviewSelectionError(message);
}

function parseArgs(argv) {
  const [command, ...argumentsList] = argv;
  if (!command) fail("usage: df-code-review-selection.mjs prepare|verify|describe|paths|validate-report-header ...");
  const values = {};
  for (let index = 0; index < argumentsList.length; index += 2) {
    const option = argumentsList[index];
    const value = argumentsList[index + 1];
    if (!option?.startsWith("--") || value === undefined || Object.hasOwn(values, option)) {
      fail(`invalid command arguments for ${command}`);
    }
    values[option.slice(2)] = value;
  }
  return { command, values };
}

function requireOptions(command, values, expected) {
  const actual = Object.keys(values).sort();
  const wanted = [...expected].sort();
  if (actual.length !== wanted.length || actual.some((key, index) => key !== wanted[index])) {
    fail(`${command}: expected options ${wanted.map((key) => `--${key}`).join(" ")}`);
  }
}

function parseSelectionRef(value) {
  const match = /^([A-Za-z0-9._-]+):sha256:([a-f0-9]{64})$/.exec(value);
  if (!match) fail("selection-ref: expected <run-id>:sha256:<64 lowercase hex digest>");
  return { runId: match[1], digest: match[2] };
}

function selectionRefText(ref) {
  return `${ref.runId}:sha256:${ref.digest}`;
}

function resolvePrdPath(prdPath, repoRoot, selection) {
  let supplied;
  let expected;
  try {
    supplied = realpathSync(isAbsolute(prdPath) ? prdPath : resolve(repoRoot, prdPath));
    expected = realpathSync(resolve(repoRoot, selection.prdPath));
  } catch (error) {
    fail(`PRD_PATH: could not resolve the selected PRD (${error.message})`);
  }
  if (supplied !== expected) {
    fail(`PRD_PATH does not resolve to the PRD bound by selection: expected ${selection.prdPath}`);
  }
}

async function loadSelection({ prdPath, selectionRef, repoRoot }) {
  const { openSelection, materializeSelection } = await import(pathToFileURL(SELECTION_HELPER).href);
  const ref = parseSelectionRef(selectionRef);
  const selection = openSelection({ ref, repoRoot });
  resolvePrdPath(prdPath, selection.repoRoot, selection);
  const entries = materializeSelection({ ref, repoRoot: selection.repoRoot, consumer: "code-review" });
  return { ref, selection, entries };
}

function bundleFor({ ref, selection, entries }) {
  return {
    schemaVersion: 1,
    consumer: "code-review",
    selection: {
      ref: selectionRefText(ref),
      runId: ref.runId,
      digest: ref.digest,
      kind: selection.kind,
      prdPath: selection.prdPath,
      ...(selection.kind === "no-user-route" ? { reason: selection.reason } : {}),
    },
    entries,
  };
}

function readBundle(inputPath) {
  let bundle;
  try {
    bundle = JSON.parse(readFileSync(inputPath, "utf8"));
  } catch (error) {
    fail(`input-path: could not read code-review selection input (${error.message})`);
  }
  if (bundle?.schemaVersion !== 1 || bundle.consumer !== "code-review" || !bundle.selection || !Array.isArray(bundle.entries)) {
    fail("input-path: invalid code-review selection input");
  }
  return bundle;
}

function describeBundle(bundle) {
  const lines = [
    "Sealed verification selection. Every listed entry is review input.",
    `- Selection ref: ${bundle.selection.ref}`,
    `- Selection digest: ${bundle.selection.digest}`,
    `- Selection kind: ${bundle.selection.kind}`,
    `- Selection PRD path: ${bundle.selection.prdPath}`,
    `- Selected entries: ${bundle.entries.length}`,
  ];
  if (bundle.selection.kind === "no-user-route") {
    lines.push(`- No-user-route reason: ${bundle.selection.reason}`);
  }
  for (const entry of bundle.entries) {
    lines.push(
      `- Entry ${JSON.stringify(entry.id)}: medium=${JSON.stringify(entry.medium)}; recipePath=${JSON.stringify(entry.recipePath)}; subFeature=${JSON.stringify(entry.subFeature)}; skillPath=${JSON.stringify(entry.skillPath)}; requirementIds=${JSON.stringify(entry.requirementIds)}; negativeRequirementIds=${JSON.stringify(entry.negativeRequirementIds)}`,
    );
  }
  return `${lines.join("\n")}\n`;
}

function reportHeaderFor(bundle) {
  return `## Sealed verification selection\n${describeBundle(bundle)}`;
}

function validateReportHeader(bundle, reportPath) {
  let report;
  try {
    report = readFileSync(reportPath, "utf8");
  } catch (error) {
    fail(`report-path: could not read reviewer report (${error.message})`);
  }
  const expected = reportHeaderFor(bundle);
  if (!report.startsWith(expected)) {
    fail("report-path: sealed selection header does not exactly match the current sealed selection");
  }
}

function pathsFor(bundle) {
  const paths = new Set([bundle.selection.prdPath]);
  for (const entry of bundle.entries) {
    paths.add(entry.skillPath);
    paths.add(entry.recipePath);
  }
  return [...paths];
}

async function main() {
  const { command, values } = parseArgs(process.argv.slice(2));
  if (command === "prepare") {
    requireOptions(command, values, ["prd-path", "selection-ref", "repo-root", "output-path"]);
    const prepared = await loadSelection({
      prdPath: values["prd-path"],
      selectionRef: values["selection-ref"],
      repoRoot: values["repo-root"],
    });
    const outputPath = resolve(values["output-path"]);
    mkdirSync(dirname(outputPath), { recursive: true });
    const temporaryPath = `${outputPath}.${process.pid}.tmp`;
    writeFileSync(temporaryPath, `${JSON.stringify(bundleFor(prepared), null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
    renameSync(temporaryPath, outputPath);
    process.stdout.write(`SELECTION_INPUT=${outputPath}\nSELECTION_DIGEST=${prepared.ref.digest}\nSELECTION_ENTRIES=${prepared.entries.length}\n`);
    return;
  }
  if (command === "verify") {
    requireOptions(command, values, ["prd-path", "selection-ref", "repo-root"]);
    const prepared = await loadSelection({
      prdPath: values["prd-path"],
      selectionRef: values["selection-ref"],
      repoRoot: values["repo-root"],
    });
    process.stdout.write(`SELECTION_DIGEST=${prepared.ref.digest}\nSTATUS=valid\n`);
    return;
  }
  if (command === "describe") {
    requireOptions(command, values, ["input-path"]);
    process.stdout.write(describeBundle(readBundle(values["input-path"])));
    return;
  }
  if (command === "paths") {
    requireOptions(command, values, ["input-path"]);
    const paths = pathsFor(readBundle(values["input-path"]));
    process.stdout.write(paths.join("\n"));
    if (paths.length > 0) process.stdout.write("\n");
    return;
  }
  if (command === "validate-report-header") {
    requireOptions(command, values, ["prd-path", "selection-ref", "repo-root", "report-path"]);
    // Report authority comes from B1, not the caller-writable bundle used to
    // construct prompts and snapshots.
    const sealed = await loadSelection({
      prdPath: values["prd-path"],
      selectionRef: values["selection-ref"],
      repoRoot: values["repo-root"],
    });
    validateReportHeader(bundleFor(sealed), values["report-path"]);
    process.stdout.write("STATUS=valid\n");
    return;
  }
  fail("usage: df-code-review-selection.mjs prepare|verify|describe|paths|validate-report-header ...");
}

main().catch((error) => {
  process.stderr.write(`df-code-review-selection: ${error.message}\n`);
  process.exitCode = 1;
});

#!/usr/bin/env node
/**
 * Immutable verification-selection storage and reader.
 *
 * A selection belongs to an existing external df run.  This helper is the
 * sole owner of its layout, canonical form, source-digest checks, and atomic
 * publication; callers only pass a draft or an explicit reference.
 */
import { createHash, randomBytes } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, realpathSync, statSync, unlinkSync, writeFileSync, linkSync } from "node:fs";
import { dirname, isAbsolute, posix, relative, resolve, sep, win32 } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const STATE_HELPER = resolve(SCRIPT_DIR, "df-state.sh");
const HASH_PATTERN = /^[a-f0-9]{64}$/;
const RUN_ID_PATTERN = /^[A-Za-z0-9._-]+$/;
const CONSUMERS = new Set(["qa-validation", "dev-verify", "code-review", "acceptance"]);

class SelectionError extends Error {}

function fail(message) {
  throw new SelectionError(message);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function exactKeys(value, keys, field) {
  if (!isObject(value)) fail(`${field}: expected an object`);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) {
    fail(`${field}: expected exactly fields ${expected.join(", ")}; got ${actual.join(", ") || "none"}`);
  }
}

function nonblank(value, field) {
  if (typeof value !== "string" || value.length === 0 || value.trim() !== value || /[\u0000-\u001f\u007f]/.test(value)) {
    fail(`${field}: expected a nonblank, trimmed string without control characters`);
  }
  return value;
}

function digest(value, field) {
  if (typeof value !== "string" || !HASH_PATTERN.test(value)) {
    fail(`${field}: expected a 64-character lowercase SHA-256 digest`);
  }
  return value;
}

function runId(value, field) {
  if (typeof value !== "string" || !RUN_ID_PATTERN.test(value) || value === "." || value === "..") {
    fail(`${field}: must match [A-Za-z0-9._-]+ and cannot be . or ..`);
  }
  return value;
}

function repositoryPath(value, field) {
  nonblank(value, field);
  if (isAbsolute(value) || win32.isAbsolute(value) || /^[A-Za-z]:/.test(value) || value.includes("\\")) {
    fail(`${field}: must be a canonical repository-relative POSIX path`);
  }
  const normalized = posix.normalize(value);
  if (normalized !== value || value === "." || value.split("/").some((part) => part === "" || part === "." || part === "..")) {
    fail(`${field}: must be a canonical repository-relative POSIX path`);
  }
  return value;
}

function uniqueSortedStrings(values, field) {
  if (!Array.isArray(values)) fail(`${field}: expected an array`);
  const normalized = values.map((value, index) => nonblank(value, `${field}[${index}]`));
  const sorted = [...normalized].sort(stringComparator);
  for (let index = 1; index < sorted.length; index += 1) {
    if (sorted[index] === sorted[index - 1]) fail(`${field}: duplicate value '${sorted[index]}'`);
  }
  return sorted;
}

// JavaScript's default localeCompare depends on the process locale. Selection
// bytes are content identity, so every selection order uses raw string code
// units instead. This also gives null sub-features an explicit stable place.
function stringComparator(left, right) {
  if (left === right) return 0;
  return left < right ? -1 : 1;
}

function nullableStringComparator(left, right) {
  if (left === null) return right === null ? 0 : -1;
  if (right === null) return 1;
  return stringComparator(left, right);
}

function hashBytes(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonicalJson(value) {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(",")}]`;
  if (isObject(value)) {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

function deepFreeze(value) {
  if (value && typeof value === "object" && !Object.isFrozen(value)) {
    Object.freeze(value);
    for (const child of Object.values(value)) deepFreeze(child);
  }
  return value;
}

function normalizeCatalogLink(value, field) {
  if (value === null) return null;
  exactKeys(value, ["path", "sha256"], field);
  return {
    path: repositoryPath(value.path, `${field}.path`),
    sha256: digest(value.sha256, `${field}.sha256`),
  };
}

function normalizeEntry(value, index, declaredMedia) {
  const field = `entries[${index}]`;
  exactKeys(value, [
    "id",
    "medium",
    "skillPath",
    "skillSha256",
    "recipePath",
    "subFeature",
    "recipeSha256",
    "requirementIds",
    "negativeRequirementIds",
  ], field);
  const medium = nonblank(value.medium, `${field}.medium`);
  if (!declaredMedia.includes(medium)) {
    fail(`${field}.medium: '${medium}' is not in declaredMedia`);
  }
  if (value.subFeature !== null) nonblank(value.subFeature, `${field}.subFeature`);
  return {
    id: nonblank(value.id, `${field}.id`),
    medium,
    skillPath: repositoryPath(value.skillPath, `${field}.skillPath`),
    skillSha256: digest(value.skillSha256, `${field}.skillSha256`),
    recipePath: repositoryPath(value.recipePath, `${field}.recipePath`),
    subFeature: value.subFeature,
    recipeSha256: digest(value.recipeSha256, `${field}.recipeSha256`),
    requirementIds: uniqueSortedStrings(value.requirementIds, `${field}.requirementIds`),
    negativeRequirementIds: uniqueSortedStrings(value.negativeRequirementIds, `${field}.negativeRequirementIds`),
  };
}

function entryComparator(left, right) {
  return stringComparator(left.medium, right.medium)
    || stringComparator(left.recipePath, right.recipePath)
    || nullableStringComparator(left.subFeature, right.subFeature)
    || stringComparator(left.id, right.id);
}

function canonicalSealedRepoRoot(value, field) {
  if (typeof value !== "string" || !isAbsolute(value)) {
    fail(`${field}: expected a canonical absolute repository root`);
  }
  let canonical;
  try {
    canonical = realpathSync(value);
  } catch {
    fail(`${field}: repository root does not exist: ${value}`);
  }
  if (canonical !== value) fail(`${field}: expected a canonical absolute repository root`);
  return canonical;
}

function normalizeSelection(value, sealed) {
  if (!isObject(value)) fail("selection: expected an object");
  const systemFields = sealed ? ["repoRoot"] : [];
  if (value.kind === "user-facing") {
    exactKeys(value, [
      "schemaVersion",
      "kind",
      "runId",
      "featureSlug",
      "prdPath",
      "prdSha256",
      "catalogLink",
      "declaredMedia",
      "entries",
      ...systemFields,
    ], "selection");
    if (value.schemaVersion !== 1) fail("selection.schemaVersion: expected 1");
    if (value.kind !== "user-facing") fail("selection.kind: expected user-facing");
    const declaredMedia = uniqueSortedStrings(value.declaredMedia, "selection.declaredMedia");
    if (declaredMedia.length === 0) fail("selection.declaredMedia: user-facing selections need at least one declared medium");
    if (!Array.isArray(value.entries) || value.entries.length === 0) {
      fail("selection.entries: user-facing selections need at least one entry");
    }
    const entries = value.entries.map((entry, index) => normalizeEntry(entry, index, declaredMedia));
    const ids = new Set();
    const identities = new Set();
    for (const entry of entries) {
      if (ids.has(entry.id)) fail(`selection.entries: duplicate entry id '${entry.id}'`);
      ids.add(entry.id);
      const identity = JSON.stringify([entry.medium, entry.recipePath, entry.subFeature]);
      if (identities.has(identity)) {
        fail(`selection.entries: duplicate recipe identity ${identity}`);
      }
      identities.add(identity);
    }
    entries.sort(entryComparator);
    const selection = {
      schemaVersion: 1,
      kind: "user-facing",
      runId: runId(value.runId, "selection.runId"),
      featureSlug: nonblank(value.featureSlug, "selection.featureSlug"),
      prdPath: repositoryPath(value.prdPath, "selection.prdPath"),
      prdSha256: digest(value.prdSha256, "selection.prdSha256"),
      catalogLink: normalizeCatalogLink(value.catalogLink, "selection.catalogLink"),
      declaredMedia,
      entries,
    };
    if (sealed) selection.repoRoot = canonicalSealedRepoRoot(value.repoRoot, "selection.repoRoot");
    return selection;
  }
  if (value.kind === "no-user-route") {
    exactKeys(value, ["schemaVersion", "kind", "runId", "featureSlug", "prdPath", "prdSha256", "reason", "entries", ...systemFields], "selection");
    if (value.schemaVersion !== 1) fail("selection.schemaVersion: expected 1");
    if (!Array.isArray(value.entries) || value.entries.length !== 0) {
      fail("selection.entries: no-user-route selections must have zero entries");
    }
    const selection = {
      schemaVersion: 1,
      kind: "no-user-route",
      runId: runId(value.runId, "selection.runId"),
      featureSlug: nonblank(value.featureSlug, "selection.featureSlug"),
      prdPath: repositoryPath(value.prdPath, "selection.prdPath"),
      prdSha256: digest(value.prdSha256, "selection.prdSha256"),
      reason: nonblank(value.reason, "selection.reason"),
      entries: [],
    };
    if (sealed) selection.repoRoot = canonicalSealedRepoRoot(value.repoRoot, "selection.repoRoot");
    return selection;
  }
  fail("selection.kind: expected user-facing or no-user-route");
}

function parseJson(bytes, field) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(`${field}: invalid JSON (${error.message})`);
  }
}

function requireRegularFile(filePath, field) {
  let metadata;
  try {
    metadata = statSync(filePath);
  } catch {
    fail(`${field}: file does not exist: ${filePath}`);
  }
  if (!metadata.isFile()) fail(`${field}: expected a regular file: ${filePath}`);
}

function resolveRepoRoot(repoRoot) {
  if (typeof repoRoot !== "string" || repoRoot.length === 0) fail("repoRoot: expected a repository root path");
  const requested = resolve(repoRoot);
  let actual;
  try {
    actual = spawnSync("git", ["-C", requested, "rev-parse", "--show-toplevel"], { encoding: "utf8" });
  } catch (error) {
    fail(`repoRoot: could not inspect git repository (${error.message})`);
  }
  if (actual.status !== 0) fail(`repoRoot: must be a git repository root (${actual.stderr.trim() || "git rev-parse failed"})`);
  const resolvedRequested = realpathSync(requested);
  const resolvedTop = realpathSync(actual.stdout.trim());
  if (resolvedRequested !== resolvedTop) fail("repoRoot: must name the git repository top level");
  return resolvedTop;
}

function resolveReferencedFile(repoRoot, repoPath, field) {
  const candidate = resolve(repoRoot, repoPath);
  const relativePath = relative(repoRoot, candidate);
  if (relativePath === "" || relativePath === ".." || relativePath.startsWith(`..${sep}`) || isAbsolute(relativePath)) {
    fail(`${field}: path escapes repository root: ${repoPath}`);
  }
  let resolvedFile;
  try {
    resolvedFile = realpathSync(candidate);
  } catch {
    fail(`${field}: referenced file does not exist: ${repoPath}`);
  }
  const resolvedRelative = relative(repoRoot, resolvedFile);
  if (resolvedRelative === "" || resolvedRelative === ".." || resolvedRelative.startsWith(`..${sep}`) || isAbsolute(resolvedRelative)) {
    fail(`${field}: symlink resolution escapes repository root: ${repoPath}`);
  }
  requireRegularFile(resolvedFile, field);
  return resolvedFile;
}

function checkFileDigest(repoRoot, repoPath, expectedDigest, field) {
  const filePath = resolveReferencedFile(repoRoot, repoPath, field);
  const actualDigest = hashBytes(readFileSync(filePath));
  if (actualDigest !== expectedDigest) {
    fail(`${field}: digest mismatch for ${repoPath}; expected ${expectedDigest}, got ${actualDigest}`);
  }
}

function checkSourceDigests(selection, repoRoot) {
  checkFileDigest(repoRoot, selection.prdPath, selection.prdSha256, "selection.prdSha256");
  if (selection.kind === "user-facing") {
    if (selection.catalogLink !== null) {
      checkFileDigest(repoRoot, selection.catalogLink.path, selection.catalogLink.sha256, "selection.catalogLink.sha256");
    }
    selection.entries.forEach((entry, index) => {
      checkFileDigest(repoRoot, entry.skillPath, entry.skillSha256, `selection.entries[${index}].skillSha256`);
      checkFileDigest(repoRoot, entry.recipePath, entry.recipeSha256, `selection.entries[${index}].recipeSha256`);
    });
  }
}

function parseRunTsv(runDirectory, expectedRunId, requireActive) {
  const runFile = resolve(runDirectory, "run.tsv");
  requireRegularFile(runFile, "run state");
  const lines = readFileSync(runFile, "utf8").replace(/\n$/, "").split("\n");
  if (lines.length !== 2) fail(`run state: expected one header and one row in ${runFile}`);
  const headers = lines[0].split("\t");
  const row = lines[1].split("\t");
  const expectedHeaders = ["run_id", "lane", "created", "finish_predicate", "artifact_sha", "budget_dispatches", "budget_wall_minutes", "state"];
  if (headers.length !== expectedHeaders.length || headers.some((header, index) => header !== expectedHeaders[index]) || row.length !== headers.length) {
    fail(`run state: invalid version-1 run.tsv at ${runFile}`);
  }
  const facts = Object.fromEntries(headers.map((header, index) => [header, row[index]]));
  if (facts.run_id !== expectedRunId) fail(`run state: run_id '${facts.run_id}' does not match '${expectedRunId}'`);
  const validStates = new Set(["running", "paused", "done", "stopped-budget", "stopped-operator"]);
  if (!validStates.has(facts.state)) fail(`run state: unknown state '${facts.state}'`);
  if (requireActive && facts.state !== "running") {
    fail(`run '${expectedRunId}' is not active (state ${facts.state}); sealing requires a running run`);
  }
}

function statePath(repoRoot, argumentsList, field) {
  const result = spawnSync("bash", [STATE_HELPER, "path", ...argumentsList], { cwd: repoRoot, encoding: "utf8" });
  if (result.status !== 0) fail(`${field}: could not locate external state (${result.stderr.trim() || "df-state path failed"})`);
  const output = result.stdout.trim();
  if (output.length === 0 || output.includes("\n")) fail(`${field}: df-state returned an invalid path`);
  return resolve(repoRoot, output);
}

function configuredStateRoot(repoRoot) {
  const stateRoot = statePath(repoRoot, [], "state store");
  let canonicalStateRoot;
  try {
    if (!statSync(stateRoot).isDirectory()) fail(`state store: expected a directory at ${stateRoot}`);
    canonicalStateRoot = realpathSync(stateRoot);
  } catch (error) {
    if (error instanceof SelectionError) throw error;
    fail(`state store: does not exist at ${stateRoot}`);
  }
  return { stateRoot, canonicalStateRoot };
}

function runDirectoryFor(repoRoot, id, requireActive) {
  runId(id, "runId");
  const { stateRoot, canonicalStateRoot } = configuredStateRoot(repoRoot);
  const runDirectory = statePath(repoRoot, [id], `run '${id}'`);
  const expectedRunDirectory = resolve(stateRoot, id);
  if (runDirectory !== expectedRunDirectory) {
    fail(`run '${id}': df-state path is not the direct named child of its configured state root`);
  }
  let resolvedRunDirectory;
  try {
    if (!lstatSync(runDirectory).isDirectory()) {
      fail(`run '${id}': state entry must be a direct non-symlink directory`);
    }
    resolvedRunDirectory = realpathSync(runDirectory);
  } catch (error) {
    if (error instanceof SelectionError) throw error;
    fail(`run '${id}': does not exist in this repository's external state store`);
  }
  if (dirname(resolvedRunDirectory) !== canonicalStateRoot) {
    fail(`run '${id}': resolved state entry escapes its configured state root`);
  }
  parseRunTsv(resolvedRunDirectory, id, requireActive);
  return resolvedRunDirectory;
}

function normalizeRef(value) {
  exactKeys(value, ["runId", "digest"], "ref");
  return { runId: runId(value.runId, "ref.runId"), digest: digest(value.digest, "ref.digest") };
}

function parseCliRef(value) {
  if (typeof value !== "string") fail("ref: expected <run-id>:sha256:<digest>");
  const match = /^([A-Za-z0-9._-]+):sha256:([a-f0-9]{64})$/.exec(value);
  if (!match) fail("ref: expected <run-id>:sha256:<64 lowercase hex digest>");
  return normalizeRef({ runId: match[1], digest: match[2] });
}

function refText(ref) {
  return `${ref.runId}:sha256:${ref.digest}`;
}

function readSealedSelection(ref, repoRoot) {
  const runDirectory = runDirectoryFor(repoRoot, ref.runId, false);
  const selectionFile = resolve(runDirectory, "verification-selections", `${ref.digest}.json`);
  let listing;
  try {
    listing = lstatSync(selectionFile);
  } catch {
    fail(`ref ${refText(ref)}: no sealed selection exists`);
  }
  if (!listing.isFile()) fail(`ref ${refText(ref)}: sealed selection must be a regular file`);
  const bytes = readFileSync(selectionFile);
  const selection = normalizeSelection(parseJson(bytes, `ref ${refText(ref)}`), true);
  const canonical = canonicalJson(selection);
  const actualDigest = hashBytes(Buffer.from(canonical, "utf8"));
  if (actualDigest !== ref.digest) {
    fail(`ref ${refText(ref)}: content digest mismatch; expected ${ref.digest}, got ${actualDigest}`);
  }
  if (bytes.toString("utf8") !== canonical) {
    fail(`ref ${refText(ref)}: stored selection is not canonical JSON`);
  }
  if (selection.runId !== ref.runId) {
    fail(`ref ${refText(ref)}: selection.runId '${selection.runId}' does not match reference run`);
  }
  if (selection.repoRoot !== repoRoot) {
    fail(`ref ${refText(ref)}: selection.repoRoot '${selection.repoRoot}' does not match supplied repository root '${repoRoot}'`);
  }
  checkSourceDigests(selection, repoRoot);
  return deepFreeze(selection);
}

export function sealSelection({ runId: suppliedRunId, draftPath, repoRoot }) {
  const root = resolveRepoRoot(repoRoot);
  const id = runId(suppliedRunId, "runId");
  if (typeof draftPath !== "string" || draftPath.length === 0) fail("draftPath: expected a path to a JSON draft");
  requireRegularFile(resolve(draftPath), "draftPath");
  const draft = normalizeSelection(parseJson(readFileSync(resolve(draftPath)), "draftPath"), false);
  if (draft.runId !== id) fail(`draftPath: selection.runId '${draft.runId}' does not match --run '${id}'`);
  checkSourceDigests(draft, root);
  const selection = { ...draft, repoRoot: root };
  const canonical = canonicalJson(selection);
  const selectionDigest = hashBytes(Buffer.from(canonical, "utf8"));
  const runDirectory = runDirectoryFor(root, id, true);
  const selectionDirectory = resolve(runDirectory, "verification-selections");
  mkdirSync(selectionDirectory, { recursive: true });
  const finalPath = resolve(selectionDirectory, `${selectionDigest}.json`);
  const tempPath = resolve(selectionDirectory, `.${selectionDigest}.${process.pid}.${randomBytes(8).toString("hex")}.tmp`);
  try {
    writeFileSync(tempPath, canonical, { encoding: "utf8", flag: "wx", mode: 0o600 });
    try {
      linkSync(tempPath, finalPath);
    } catch (error) {
      if (error.code !== "EEXIST") throw error;
      const existing = readFileSync(finalPath, "utf8");
      const existingSelection = normalizeSelection(parseJson(existing, `ref ${id}:sha256:${selectionDigest}`), true);
      if (existingSelection.repoRoot !== root) {
        fail(`ref ${id}:sha256:${selectionDigest}: existing selection belongs to '${existingSelection.repoRoot}', not '${root}'`);
      }
      if (existing !== canonical) {
        fail(`ref ${id}:sha256:${selectionDigest}: refusing to overwrite differing existing content`);
      }
    }
  } finally {
    if (existsSync(tempPath)) unlinkSync(tempPath);
  }
  return deepFreeze({ runId: id, digest: selectionDigest });
}

export function openSelection({ ref, repoRoot }) {
  const root = resolveRepoRoot(repoRoot);
  return readSealedSelection(normalizeRef(ref), root);
}

export function materializeSelection({ ref, repoRoot, consumer }) {
  if (!CONSUMERS.has(consumer)) {
    fail("consumer: expected qa-validation, dev-verify, code-review, or acceptance");
  }
  const selection = openSelection({ ref, repoRoot });
  return deepFreeze(selection.entries.map((entry) => ({ ...entry })));
}

function parseCommand(argv) {
  const [command, ...argumentsList] = argv;
  if (!command) fail("usage: df-selection.mjs seal|inspect|materialize ...");
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

function main() {
  const { command, values } = parseCommand(process.argv.slice(2));
  if (command === "seal") {
    requireOptions(command, values, ["run", "draft", "repo-root"]);
    const ref = sealSelection({ runId: values.run, draftPath: values.draft, repoRoot: values["repo-root"] });
    process.stdout.write(`SELECTION_REF=${refText(ref)}\nENTRIES=${openSelection({ ref, repoRoot: values["repo-root"] }).entries.length}\nSTATUS=sealed\n`);
    return;
  }
  if (command === "inspect") {
    requireOptions(command, values, ["ref", "repo-root"]);
    process.stdout.write(`${JSON.stringify(openSelection({ ref: parseCliRef(values.ref), repoRoot: values["repo-root"] }), null, 2)}\n`);
    return;
  }
  if (command === "materialize") {
    requireOptions(command, values, ["ref", "repo-root", "consumer", "format"]);
    const entries = materializeSelection({ ref: parseCliRef(values.ref), repoRoot: values["repo-root"], consumer: values.consumer });
    if (values.format === "json") {
      process.stdout.write(`${JSON.stringify(entries, null, 2)}\n`);
      return;
    }
    if (values.format === "paths") {
      // Each JSON tuple is [medium, recipePath, subFeature], one recipe leg per
      // line. It is machine-parseable and cannot collapse distinct sub-features.
      process.stdout.write(entries.map((entry) => JSON.stringify([entry.medium, entry.recipePath, entry.subFeature])).join("\n"));
      if (entries.length > 0) process.stdout.write("\n");
      return;
    }
    fail("format: expected json or paths");
  }
  fail("usage: df-selection.mjs seal|inspect|materialize ...");
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    main();
  } catch (error) {
    process.stderr.write(`df-selection: ${error.message}\n`);
    process.exitCode = 1;
  }
}

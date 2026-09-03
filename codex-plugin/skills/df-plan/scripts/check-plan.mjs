#!/usr/bin/env node
// Checks a df plan against the shape in ../references/plan-skeleton.md.
// Plain node, no dependencies. Exit 0 clean, 1 with defects, 2 on usage error.
// The D5 gate line on stdout is a routing signal, not a defect.
import fs from "node:fs";
import process from "node:process";

const RULE =
	"Tests alone are not sufficient verification. A PR is verified only when its unit, live, and perf boxes are all checked.";
const TASK_CAP = 8;
const PR_BLOCKS = ["Depends on.", "Branch.", "Budget.", "You see.", "Verify, unit.", "Verify, live.", "Verify, perf."];
const TASK_BLOCKS = ["Files.", "Interfaces.", "Steps."];
const HEADER_FIELDS = ["Goal.", "Spec.", "Design.", "Lane."];
const PERF_ITEMS = ["Metric.", "Probe.", "Baseline.", "Rule."];
const NOT_PERF = "Not perf-sensitive.";
const HOW_TO_READ_MARKERS = [
	"One box is one unit of work",
	"names the evidence",
	"Check a box only when its evidence exists",
	"df-implement",
	RULE,
];
const PLACEHOLDER_WORDS = [
	[/\bTBD\b/, "TBD"],
	[/\bTODO\b/, "TODO"],
	[/implement later/i, "implement later"],
	[/fill in details/i, "fill in details"],
	[/add appropriate/i, "add appropriate"],
	[/handle edge cases/i, "handle edge cases"],
	[/similar to Task/i, "similar to Task"],
];
const BOX = /^\s*- \[[ x]\] (.*)$/;
const ITEM = /^\s*- \S/;
const PR_TITLE = /\((PR-[A-Za-z0-9._-]+)\)$/;
const TASK_H = /^### Task (\d+)\. (.+)$/;

const file = process.argv[2];
if (!file) {
	console.error("Usage: node check-plan.mjs <plan.md>");
	process.exit(2);
}

const raw = fs.readFileSync(file, "utf8").split(/\r?\n/);
const problems = [];
const fail = (line, message) => problems.push(`${file}:${line}: ${message}`);

let start = 0;
if (raw[0] === "---") {
	start = raw.indexOf("---", 1) + 1;
}

const lines = [];
let fence = false;
for (let i = start; i < raw.length; i++) {
	const text = raw[i];
	const n = i + 1;
	if (/^```/.test(text)) fence = !fence;
	lines.push({ n, text, code: fence });
	for (const [re, name] of PLACEHOLDER_WORDS) {
		if (re.test(text)) fail(n, `placeholder "${name}"`);
	}
	if (fence) continue;
	const prose = text
		.replace(/`[^`]*`/g, "`")
		.replace(/!\[[^\]]*\]\([^)]*\)/g, "")
		.replace(/\]\([^)]*\)/g, "]");
	if (/[–—]/.test(prose)) fail(n, "long dash");
	if (/[‘’“”]/.test(prose)) fail(n, "curly quote");
	if (/: \S/.test(prose)) fail(n, "mid-sentence colon");
	if (/superpowers/i.test(prose)) fail(n, "names a superpowers skill; the executor is df-implement");
	if (/<[A-Za-z][^<>]*>/.test(prose) && !/:\/\//.test(prose)) fail(n, "unfilled angle-bracket placeholder");
}

const sections = [];
for (const l of lines) {
	if (!l.code && l.text.startsWith("## ")) sections.push({ title: l.text.slice(3).trim(), n: l.n, body: [] });
	else if (sections.length) sections.at(-1).body.push(l);
}
const find = (title) => sections.find((s) => s.title === title);
const bodyText = (s) => s.body.map((l) => l.text).join("\n");
const boxes = (ls) => ls.filter((l) => !l.code && BOX.test(l.text)).map((l) => ({ n: l.n, text: l.text.match(BOX)[1] }));
const items = (ls) => ls.filter((l) => !l.code && ITEM.test(l.text));

const h1 = lines.findIndex((l) => !l.code && l.text.startsWith("# "));
if (h1 === -1) fail(1, "no H1 title");
const howToRead = find("How to read this");
if (!howToRead) fail(1, 'no "## How to read this" section');
if (h1 !== -1 && howToRead) {
	const intro = lines.slice(h1 + 1).filter((l) => l.n < howToRead.n && l.text.trim() !== "");
	if (intro.length > 12) fail(lines[h1].n, `intro is ${intro.length} non-empty lines, 12 is the cap`);
	for (const f of HEADER_FIELDS) {
		const fieldLine = intro.find((l) => l.text.startsWith(`**${f}**`));
		if (!fieldLine) fail(lines[h1].n, `intro lacks a "**${f}**" line`);
		else if (fieldLine.text.slice(f.length + 4).trim() === "") fail(fieldLine.n, `"**${f}**" line is empty`);
	}
	for (const marker of HOW_TO_READ_MARKERS) {
		if (!bodyText(howToRead).includes(marker)) fail(howToRead.n, `How to read this lacks "${marker}"`);
	}
}

const globals = find("Global constraints");
if (!globals) fail(1, 'no "## Global constraints" section');
if (globals && howToRead && globals.n < howToRead.n) fail(globals.n, "Global constraints comes before How to read this");

const prSections = sections.filter((s) => PR_TITLE.test(s.title));
if (prSections.length === 0) fail(1, "no PR blocks; an H2 title ending in (PR-<id>) opens each one");
if (globals) {
	let seenAppendix = false;
	for (const s of sections.slice(sections.indexOf(globals) + 1)) {
		if (PR_TITLE.test(s.title)) {
			if (seenAppendix) fail(s.n, `"## ${s.title}" comes after an appendix`);
		} else if (s.title.startsWith("Appendix")) {
			seenAppendix = true;
		} else {
			fail(s.n, `"## ${s.title}" is neither a PR block nor an appendix`);
		}
	}
}

const report = [];
const allTasks = [];
for (const pr of prSections) {
	const heads = [];
	const tasks = [];
	let curPr = null;
	let curTask = null;
	let curTaskBlock = null;
	const attach = (l) => {
		if (curTaskBlock) curTaskBlock.lines.push(l);
		else if (curTask) curTask.lines.push(l);
		else if (curPr) curPr.lines.push(l);
	};
	for (const l of pr.body) {
		if (!l.code) {
			const th = l.text.match(TASK_H);
			if (th) {
				curTask = { num: Number(th[1]), title: th[2], n: l.n, heads: [], lines: [] };
				tasks.push(curTask);
				allTasks.push(curTask);
				curPr = null;
				curTaskBlock = null;
				continue;
			}
			const m = l.text.match(/^\*\*([^*]+)\*\*(.*)$/);
			if (m && PR_BLOCKS.includes(m[1])) {
				curPr = { name: m[1], n: l.n, rest: m[2].trim(), lines: [] };
				heads.push(curPr);
				curTask = null;
				curTaskBlock = null;
				continue;
			}
			if (m && TASK_BLOCKS.includes(m[1]) && curTask) {
				curTaskBlock = { name: m[1], n: l.n, rest: m[2].trim(), lines: [] };
				curTask.heads.push(curTaskBlock);
				continue;
			}
			if (l.text.startsWith("### ")) {
				fail(l.n, `${pr.title}: heading "${l.text.slice(4).trim()}" is not "Task <n>. <name>"`);
				continue;
			}
		}
		attach(l);
	}

	const names = heads.map((h) => h.name);
	if (names.join("|") !== PR_BLOCKS.join("|")) {
		fail(pr.n, `${pr.title}: blocks are [${names.join(", ")}], expected [${PR_BLOCKS.join(", ")}]`);
	}
	const block = (name) => heads.find((h) => h.name === name);

	const depends = block("Depends on.");
	if (depends && depends.rest === "") fail(depends.n, `${pr.title}: Depends on names nothing`);
	const branch = block("Branch.");
	if (depends && branch) {
		if (depends.rest === "None." && branch.rest !== "Independent from main.") {
			fail(branch.n, `${pr.title}: an independent PR must say "Branch. Independent from main."`);
		} else if (depends.rest !== "None.") {
			const dependency = depends.rest.match(/^(PR-[A-Za-z0-9._-]+)\.$/);
			if (!dependency) {
				fail(depends.n, `${pr.title}: Depends on must be "None." or one PR id`);
			} else if (branch.rest !== `Dependent on ${dependency[1]}.`) {
				fail(branch.n, `${pr.title}: Branch must say "Dependent on ${dependency[1]}."`);
			}
		}
	}

	const budget = block("Budget.");
	if (budget && budget.rest === "" && budget.lines.every((l) => l.text.trim() === "")) {
		fail(budget.n, `${pr.title}: Budget note is empty; source it from the run state`);
	}

	const see = block("You see.");
	if (see && boxes(see.lines).length === 0) fail(see.n, `${pr.title}: You see has no box`);

	if (tasks.length === 0) fail(pr.n, `${pr.title}: no tasks`);
	const unit = block("Verify, unit.");
	if (see && unit) {
		for (const t of tasks) {
			if (t.n < see.n || t.n > unit.n) fail(t.n, `${pr.title}: Task ${t.num} sits outside the You see to Verify span`);
		}
	}

	for (const name of ["Verify, unit.", "Verify, live.", "Verify, perf."]) {
		const b = block(name);
		if (b && !b.rest.startsWith(RULE)) fail(b.n, `${pr.title}: ${name} does not open with the verification rule`);
	}

	if (unit) {
		const ub = boxes(unit.lines);
		if (ub.length === 0) fail(unit.n, `${pr.title}: Verify, unit has no box`);
		for (const b of ub) {
			if (!/Run `[^`]+`/.test(b.text)) fail(b.n, `${pr.title}: unit box names no command with Run \`...\``);
		}
	}

	const live = block("Verify, live.");
	if (live) {
		const lb = boxes(live.lines);
		if (lb.length === 0) fail(live.n, `${pr.title}: Verify, live has no box; the live block is mandatory`);
		for (const b of lb) {
			if (!/Save `[^`]+`/.test(b.text)) fail(b.n, `${pr.title}: live box names no evidence file with Save \`...\``);
			if (!b.text.includes("Pass when")) fail(b.n, `${pr.title}: live box has no "Pass when" predicate`);
		}
	}

	const perf = block("Verify, perf.");
	if (perf) {
		const after = perf.rest.startsWith(RULE) ? perf.rest.slice(RULE.length).trim() : perf.rest;
		const pb = boxes(perf.lines);
		if (after.startsWith(NOT_PERF)) {
			if (after.slice(NOT_PERF.length).trim() === "") fail(perf.n, `${pr.title}: ${NOT_PERF} needs its one-line reason`);
			if (pb.length) fail(perf.n, `${pr.title}: ${NOT_PERF} but perf boxes exist`);
		} else {
			const first = pb.map((b) => b.text.split(" ")[0]);
			if (first.join("|") !== PERF_ITEMS.join("|")) {
				fail(perf.n, `${pr.title}: perf boxes are [${first.join(", ")}], expected [${PERF_ITEMS.join(", ")}]`);
			}
		}
	}

	for (const t of tasks) {
		const tn = t.heads.map((h) => h.name);
		if (tn.join("|") !== TASK_BLOCKS.join("|")) {
			fail(t.n, `${pr.title}: Task ${t.num} blocks are [${tn.join(", ")}], expected [${TASK_BLOCKS.join(", ")}]`);
		}
		const tb = (name) => t.heads.find((h) => h.name === name);
		const files = tb("Files.");
		if (files && items(files.lines).length === 0) fail(files.n, `${pr.title}: Task ${t.num} Files has no entry`);
		const ifc = tb("Interfaces.");
		if (ifc && items(ifc.lines).length === 0) fail(ifc.n, `${pr.title}: Task ${t.num} Interfaces has no entry`);
		const steps = tb("Steps.");
		if (steps && boxes(steps.lines).length === 0) fail(steps.n, `${pr.title}: Task ${t.num} Steps has no box`);
	}

	report.push(`${pr.title}  tasks=${tasks.length}  boxes=${boxes(pr.body).length}`);
}

const nums = allTasks.map((t) => t.num);
const want = nums.map((_, i) => i + 1);
if (nums.length && nums.join(",") !== want.join(",")) {
	fail(allTasks[0].n, `task numbers are [${nums.join(",")}], expected 1 to ${nums.length} in document order`);
}

for (const line of report) console.log(line);
console.log(`${prSections.length} PR blocks, ${allTasks.length} tasks, ${problems.length} problems`);
if (allTasks.length > TASK_CAP) {
	console.log(`D5 gate: ${allTasks.length} tasks is over ${TASK_CAP}. Operator sign-off required before implementation.`);
}
for (const p of problems) console.error(p);
process.exit(problems.length ? 1 : 0);

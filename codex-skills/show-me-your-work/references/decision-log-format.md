# Decision log format

`decision-log-template.tsv` is the header row for `decisions.tsv`. Columns:

- `ts`: ISO-8601 timestamp.
- `phase`: the playbook step or stage the decision belongs to.
- `decision`: what was chosen, one line.
- `why`: the reason, one line.
- `evidence`: a pointer (file path, commit SHA, PR number, command output path), never a
  pasted blob.
- `result`: what happened, filled in when known.

Append-only. `scripts/log.sh` writes rows and hardens against spreadsheet formula
injection: tabs stripped from field values, a leading `=` quoted.

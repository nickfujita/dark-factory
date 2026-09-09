# User-facing proof boundaries

Apply these rules to a feature recipe's opening description, sub-features, and
"How to get to it" prose. Those sections describe the user's contract, not the
implementation. The "Driving it with <harness>" section and programmatic test
specifications may name selectors, commands, endpoints, and technical fixtures.

## Decide what the user actually sees

The declared medium determines what is public. Do not apply browser-only rules
to a terminal, protocol, library, or service consumer.

- Browser users see labels, navigation, displayed results, and public URLs.
  React state setters and hidden internal routes are not user actions.
- CLI and TUI users see commands, flags, prompts, keyboard actions, output,
  files, exit codes, and documented environment settings.
- API and MCP consumers see the documented transport, request and response
  schemas, tool names, authentication requirements, errors, and status codes.
- Library consumers see public signatures, return values, and exceptions.
  An internal module symbol is not public merely because a test imports it.

For example, a documented CLI format flag or an API's authorization error may
belong in user-POV prose. A database table name does not belong there unless the
product actually exposes that table as its supported user interface.

## Keep implementation out of user-POV assertions

Do not prove public behavior by asserting a private method call, database
mutation, cache entry, queue dispatch, or internal UI state. State the observable
contract instead. Test IDs may help locate a visible control in the driving
section; they are not the behavior the user is verifying.

Setup and supporting observations may inspect internals where authorized.
Keep them distinct from acceptance through the chosen medium. For a browser
action, a successful API request cannot substitute for operating the UI.

## Handle a violation

Route planned recipe edits to `create-verification-skill` in planned-recipe
operation. Route drift in already-implemented recipes to
`maintain-verification-skill`. Preserve the intended requirement.

A requirement with no user-facing medium may still be proved by unit,
integration, or protocol tests. Label it programmatic-only. Use UNTESTABLE only
when there is no defensible proof, with the concrete reason. Lack of browser
wording is not lack of testability.

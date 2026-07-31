---
name: go-mobile
description: "Use when the user is mobile, or hints at it — 'go mobile', 'going mobile', 'heading out', 'on my phone', voice-dictation artifacts or garbled typos, or a message arriving via the phone bridge — or runs /go-mobile. Switches every later reply to a spoken, TTS-safe style until stop-mobile. Optional 'repeat' argument re-delivers the previous reply in spoken form."
---

# Go Mobile

Switch into mobile / text-to-speech mode. The user has moved to a phone or an
audio-only setup and will **hear** your replies read aloud. An on-complete hook
reads only your **final message** of each turn — nothing else reaches them.
Stay in this mode for the rest of the session until the user runs `stop-mobile`
(or clearly says they are back at a desktop).

## Argument

- **No argument** — switch into mobile mode starting with your next response. Do
  not repeat anything; just acknowledge the switch in one spoken sentence and
  continue.
- **`repeat`** — the user changed devices after your last reply and could not
  hear it. Immediately re-deliver the content of your previous response,
  rewritten in the spoken style below, as your final message. Then stay in
  mobile mode.

## How to write every response in mobile mode

Write the way you would say it out loud to someone who can only listen:

- **Put everything that matters in the final message of the turn.** That is the
  only thing the user hears. Do not split important content across tool-call
  narration or earlier messages.
- **No symbols that don't read aloud:** no markdown headers or hashes, no
  bullet-point characters, no bold or italic markers, no emoji. If you need to
  list things, say them as a spoken sequence — "first… then… and finally…".
- **No URLs, links, file paths, directory names, code, or inline code.** Refer
  to them in plain words instead — say "the code review skill" or "your global
  settings", not the literal path or command.
- **No tables.** State the comparison in a sentence or two.
- **Lead with the answer**, then the why. Keep it concise — listening is slower
  than reading, so do not pad.
- If a specific path, command, link, or block of code is genuinely needed, do
  not read it aloud. Say what it is in words and offer to send the exact text
  when they are back at a desktop.

## Red flags — you are slipping out of mobile mode

- About to print a file path, URL, or code block → describe it in words instead.
- Writing a markdown header or a bulleted list → say it as flowing speech.
- Relying on an earlier message or tool output to carry meaning → move it into
  the final message; that is all they hear.

Keep applying this style to every response until `stop-mobile`.

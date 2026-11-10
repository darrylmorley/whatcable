# Translations

WhatCable ships in 20 languages. Community translations are welcome and
credited in the release notes. A few ground rules keep them mergeable.

## The one rule that matters

**Technical and protocol labels stay in English. Explanatory prose gets
translated.**

Labels like `RDO`, `PDO`, `CC Advertisement`, `Raw VDOs`, `e-marker`,
`SOP'`, Thunderbolt generation names, and diagnostic field names must match
what users see in USB-PD and USB-IF specs, IOKit output, logs, and system
reports. Translating them breaks that link. If you're unsure whether a term
is a label or prose: would someone paste it into a search engine alongside a
spec document? Then it stays English.

Everything else (sentences explaining what's wrong, advice, summaries)
should read naturally in your language. Don't translate word-for-word from
English.

## Where the strings live

- `Sources/WhatCableCore/Resources/<lang>.lproj/Localizable.strings` (CLI + shared)
- `Sources/WhatCable/Resources/<lang>.lproj/Localizable.strings` (app UI)

Keys must match `en.lproj` exactly, including format specifiers (`%@`,
`%lld`). Positional forms (`%1$@`) are fine where your grammar needs
reordering. The test suite checks parity on every PR.

## Maintained languages

Some languages have an active maintainer whose terminology decisions stand.
PRs in these languages wait for the maintainer's review before merging:

- Traditional Chinese (zh-Hant): @jimmyorz
- Italian (it): @bovirus

If you'd like to be listed as the maintainer for a language you've been
contributing to, say so in a PR or issue.

## Before opening a PR

1. Read the existing translation first. Match its established terminology,
   don't re-litigate it.
2. Change values only, never keys.
3. One language per PR.

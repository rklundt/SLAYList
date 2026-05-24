# Contributing to SLAYList

SLAYList is a private family project published under [AGPL-3.0-or-later](LICENSE). It is not seeking contributions, but if you do open a pull request, the terms below apply.

## Inbound license + relicensing grant

By submitting a pull request, issue patch, or any other contribution to this repository, you certify and agree to **both** of the following:

1. **The Developer Certificate of Origin, version 1.1** (full text at <https://developercertificate.org/>). In short: you wrote the code, or have the right to submit it under the project's open-source license, and you understand the contribution and the record of it is public.

2. **Relicensing grant.** You agree that your contribution may be relicensed by the project maintainer (Ray Klundt) under any [OSI-approved](https://opensource.org/licenses) open-source license, in addition to AGPL-3.0-or-later. This preserves the project's option to change licenses in the future without tracking down every past contributor for consent.

You retain copyright on your contribution. This grant is non-exclusive and irrevocable for the contribution submitted.

## How to sign off

Add a `Signed-off-by` line to every commit. Git can do this automatically with `-s`:

```
git commit -s -m "your message"
```

The resulting commit will end with:

```
Signed-off-by: Your Name <your.email@example.com>
```

That sign-off is your acknowledgement of both the DCO and the relicensing grant above. Pull requests without sign-offs on every commit will not be merged.

## File headers

Every source file in this repository carries a two-line header:

```
// Copyright (c) <year> Ray Klundt
// SPDX-License-Identifier: AGPL-3.0-or-later
```

Use the comment syntax appropriate for the file's language. The header is checked at sprint review (`/wrap-sprint`). New contributors do not add their own copyright line; the relicensing grant above keeps the copyright line stable.

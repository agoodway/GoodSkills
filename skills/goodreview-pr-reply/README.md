# goodreview-pr-reply

Posts a [`goodreview`](../goodreview/README.md) report to the current branch's pull request as one GitHub review: an overview comment with the verdict, and an inline comment on the changed line for each finding.

## Install

```bash
npx skills add agoodway/GoodSkills --skill goodreview --skill goodreview-pr-reply
```

Requires the `gh` CLI, installed and authenticated.

## Usage

Run `/goodreview` first, then:

```
/goodreview-pr-reply                              # post every finding
/goodreview-pr-reply blockers only                # pick findings with a prompt
/goodreview-pr-reply 1 and 3, skip the test one
```

The skill shows the full draft and waits for approval before posting. It posts with the `COMMENT` event and never approves, requests changes, or resolves threads.

## What gets posted

- The overview has the verdict, a sketch of the change marked with where each finding lands, a table of the posted findings, the checks that ran, and the merge danger.
- Each finding whose line is in the pull request's diff gets an inline comment with a view of the failure (a trace tree, a sequence diagram, or pseudocode) and a fix. When the fix replaces exactly the commented lines, it is a GitHub suggestion the author can apply in one click.
- A finding whose line is not in the diff goes in the overview.
- Every comment opens with a note naming the model and the user it is posting for.

# Thread mode

With `--threads`, each frontier ticket runs in a **child**: a T3 Code child thread or an Amp orb. Children run in parallel, each on its own ticket branch, and you integrate their commits onto the run branch. Everything in `SKILL.md` still applies except **Scheduling (default mode)**, which this file replaces.

## Pick the runtime

- **T3 Code**: the `delegate_task` tool is available (load T3 tools with ToolSearch if they are deferred). Call `orchestrator_capabilities` once before the first `delegate_task`.
- **Amp**: the `amp` CLI is on `PATH`, or you are an Amp agent that can start orb threads.
- Anything else: stop and say thread mode needs T3 Code or Amp. Do not fall back to serial.

## Before the first child

1. Run the rebase from `SKILL.md`.
2. Push the run branch: `git push -u origin HEAD`. Children build from `origin`.
3. **Amp only**: an orb is a remote machine that clones the repo, so it sees only project-installed skills. Check that `openspec-ship-tickets`, `goodreview`, `git`, and the four OpenSpec skills exist under the repo's skill directory. When any is missing, stop and print the install commands, for example `npx skills add agoodway/GoodSkills --skill openspec-ship-tickets` (and `goodreview`, `git`), plus `openspec init` or `openspec update` for the OpenSpec skills.

## Schedule

Keep up to `--parallel` children running (default 3). Whenever a slot is free, start a child for the next frontier ticket in `tickets.md` order, and move that ticket to in progress on the tracker. A ticket joins the frontier only after every blocker has **landed** (integrated onto the run branch and pushed), never when a blocker's child merely finishes.

### Child prompt

Each child gets one standalone prompt:

```text
/openspec-ship-tickets --worker <ticket> --base <run-branch> [--store <id>]

<ticket brief: reference, title, tracker body verbatim, covered scenarios, change name and path>
```

In T3 Code, also tell the child the base: its worktree must start from `origin/<run-branch>`.

### Start it

- **T3 Code**: `delegate_task` with `isolation: "worktree"` and the child prompt. Follow the returned `next`; results arrive as notifications. Do not poll.
- **Amp**: prefer Amp's agent-to-agent handoff: start an orb thread with the child prompt and ask it to report back when it finishes. From a shell, run `amp -ox "<child prompt>" --stream-json` as a background command, one per child; the stream ends when the child's turn ends, and its last assistant message carries the status block. Record each thread URL.

### When a child reports

Read its final status block.

- `STATUS: done`: confirm the branch exists (`git ls-remote origin <branch>`), then integrate it.
- `STATUS: blocked`: handle it as a blocked ticket per `SKILL.md`. Its dependents are skipped. Other children keep running.
- No status block, or a lost child: inspect the remote branch and the child's thread before deciding. Push state decides; do not restart a child whose branch already holds a finished commit.

## Integrate

Integrate one ticket at a time, in blocking order, on the run branch in this checkout:

1. `git fetch origin <branch>`, then `git cherry-pick` its commit(s) onto the run branch.
2. On a conflict, start one subagent on the run branch. It resolves the conflict within both tickets' intent, reruns the checks covering both tickets, and completes the cherry-pick. If it cannot resolve the conflict safely, it aborts the cherry-pick (`git cherry-pick --abort`) and returns `STATUS: blocked`; treat the ticket as blocked.
3. `git push origin HEAD`.
4. Comment the landed commit on the ticket, delete the ticket branch (`git push origin --delete <branch>`), mark the ticket landed, and recompute the frontier.
5. When the ticket's change has no open tickets left, run **Close out a change** on the run branch now, then push again.

Close-out and integration share this checkout, so run them one at a time; children keep running meanwhile.

## Finish

When no child is running and the frontier is empty, run the pull request step from `SKILL.md`. Add each child's thread link to the per-ticket summary.

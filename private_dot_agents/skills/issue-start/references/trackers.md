# Tracker ownership

Use the available Linear and Sentry tools; their names depend on the agent's installed integrations. Skip a tracker the project does not use. If access is unavailable, report the unchecked work and continue orientation.

Invoking `/issue-start` authorizes the assignments and linking below. Reading or editing the skill does not. Resolve the user's identity in each tracker before assigning work.

## Linear

Fetch the resolved issue's current assignee and resolve the current user with `me`.

| Assignee | Action |
|---|---|
| Unassigned | Assign the user. |
| The user | Ownership is already correct. |
| Someone else | Apply an explicitly authorized assignment change from the invocation or conversation. Otherwise ask whether to leave ownership as-is or reassign to the user, and wait before changing it. |

## Sentry

If the handoff names a Sentry issue, confirm it is assigned to the user and assign it if needed.

Otherwise, search once using the handoff's error text, affected module, or in-scope app. A relevant match shares the error, stack frame, or component.

- One clearly relevant issue: assign it to the user, add its URL and short ID in a comment on the Linear issue when one exists, and record them in the session summary when one exists. Reuse an existing link instead of posting a duplicate.
- Multiple candidates: list them and ask which applies before assigning or linking.
- No clear match: continue without a Sentry issue.

When a Sentry issue applies, include its URL and short ID in the orientation and state that the GitHub PR description must reference it, for example with `Fixes: {URL}`. Ownership checks are complete once assignments and required links are confirmed, or the user chooses to leave an existing assignment unchanged.

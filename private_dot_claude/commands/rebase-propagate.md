====<rebase-propagate-command>====
git fetch origin, update this branch to be on top of origin/staging (ask me how to resolve any conflicts).

If there is a PR already, update that one, and also check for any dependent PRs targeting that one, and propagate the updates (again, asking me for any conflict resolution).
There used to be an auto-pr workflow, so schedule a small check if any dupes appear after we push, and delete them if clear dupes. Anything that isn't clearly such a dupe, ask the user about it.
====</rebase-propagate-command>====

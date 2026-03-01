## Git Commits

Follow conventional commits when writing git commits.

## PR Comments

<pr-comment-rule>
When I say to add a comment to a PR with a TODO on it, use 'checkbox' markdown format to add the TODO. For instance:

<example>
- [ ] A description of the TODO goes here
</example>
</pr-comment-rule>
- When tagging Claude in GitHub issues, use '@claude'

## Change sets

To add a change set, write a new file to the `.changeset` directory.

The file should be named `0000-your-change.md`. Decide yourself whether to make it a patch, minor, or major change.

The format of the file should be:

```md
---
Relevant front-matter
---


Description of the change.
```

## GitHub

- Your primary method for interacting with GitHub should be the GitHub CLI.

## Git

- When creating branches, prefix them with `AbysmalBiscuit-claude/` to indicate they came from me and claude.

## Plans

- At the end of each plan, give me a list of unresolved questions to answer, if any.


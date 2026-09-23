# Link a PR to an issue by hand

GitHub turns `Closes #N` in a PR body into a link only when the PR targets the default branch. A stacked PR never gets linked that way, and neither does a PR in another repo than the issue. Create the link with the GraphQL `addCloseIssueReferences` mutation. It makes the same link the issue's Development sidebar shows, and it works across repos.

Look up both node IDs, then run the mutation:

```sh
issue=$(gh api graphql -f query='{ repository(owner:"ISSUE_OWNER",name:"ISSUE_REPO"){ issue(number:ISSUE_NUMBER){ id } } }' --jq .data.repository.issue.id)
pr=$(gh api graphql -f query='{ repository(owner:"PR_OWNER",name:"PR_REPO"){ pullRequest(number:PR_NUMBER){ id } } }' --jq .data.repository.pullRequest.id)
gh api graphql -f query="mutation { addCloseIssueReferences(input:{issueId:\"$issue\", pullRequestIds:[\"$pr\"]}) { clientMutationId } }"
```

The mutation can return success without creating the link. Read it back, and rerun the mutation while the list comes back empty:

```sh
gh api graphql -f query='{ repository(owner:"ISSUE_OWNER",name:"ISSUE_REPO"){ issue(number:ISSUE_NUMBER){ closedByPullRequestsReferences(first:5,includeClosedPrs:true){ nodes{ number repository{ nameWithOwner } } } } } }'
```

The link is done when the PR's number and repo appear in `nodes`.

`removeCloseIssueReferences` takes the same input and removes the link.

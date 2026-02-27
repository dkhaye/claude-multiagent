# Review Standards

> Maintained by the Reviewer agent. Checklist and common mistakes captured across reviews.

## Review checklist

- [ ] Code does what the PR description claims
- [ ] No hardcoded secrets or credentials
- [ ] No over-permissive IAM/auth scopes
- [ ] Error cases are handled
- [ ] CI/CD workflow has `pull_request` trigger (plans run on PRs)
- [ ] Action versions are pinned (SHA or major version tag)
- [ ] PR description and commit messages are clear and complete
- [ ] No unrelated changes included in the diff

## Common mistakes

_Append entries here as they are discovered._

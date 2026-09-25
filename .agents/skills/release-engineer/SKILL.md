---
name: release-engineer
description: Prepare and publish Medusa releases through the repository's RubyGems trusted-publishing and immutable GitHub Release workflow. Use when cutting, validating, tagging, publishing, or recovering a Medusa release.
---

# Medusa Release Engineer

You are the release engineer for Medusa, the `medusa-crawler` Ruby gem.

Your job is to make releases boring, reproducible, and difficult to publish incorrectly.

This skill is adapted from Blackwell Systems' `oss-kit` release-engineer skill (MIT licensed), but the process below is intentionally Medusa-specific.

## Source of Truth

Before changing release metadata, read:

- `AGENTS.md`
- `CHANGELOG.md`
- `VERSION`
- `lib/medusa/version.rb`
- `medusa.gemspec`
- `.github/workflows/ruby.yml`
- `.github/workflows/publish-gem.yml`

Do not assume a generic RubyGems or GitHub release flow. Follow the repository's actual workflows.

## Non-Negotiable Invariants

A Medusa release is valid only when all of these are true:

1. `VERSION`, `Medusa::VERSION`, and `medusa.gemspec` contain the exact same version.
2. The git tag is exactly `v<VERSION>`, including the leading `v`.
3. The tag points at the exact merged `main` commit containing that version.
4. The full release CI passes on the tagged commit.
5. RubyGems publishing succeeds before a GitHub Release is created.
6. The GitHub Release uses the same `v<VERSION>` tag.
7. A prerelease version such as `2.0.0.pre.4` is marked as a GitHub prerelease.

The leading `v` is mandatory. The publish workflow triggers only for `v*` tags, and the gemspec's `source_code_uri` also points to `v#{s.version}`.

## Release Ordering

The order is part of correctness.

Always use this sequence:

1. Prepare release metadata on a release branch.
2. Open a PR.
3. Let PR CI pass.
4. Merge the PR to `main`.
5. Verify `main` contains the intended version in all three version sources.
6. Verify the merge commit's `main` CI is green.
7. Create and push tag `v<VERSION>` on that exact `main` commit.
8. Wait for the tag-triggered `Publish gem` workflow to finish successfully.
9. Verify the new version exists on RubyGems.
10. Only then create the GitHub Release.

Never create the GitHub Release before RubyGems publishing succeeds.

Medusa uses immutable GitHub Releases. Treat a published release version/tag name as permanently consumed even if the release is later deleted. If an immutable release is created incorrectly, advance to the next version rather than trying to recycle the old release name.

## Versioning

Medusa follows semantic versioning for stable releases.

For the 2.0 prerelease line, use:

```
2.0.0.pre.N
```

and tag it as:

```
v2.0.0.pre.N
```

Examples:

- gem version: `2.0.0.pre.4`
- git tag: `v2.0.0.pre.4`

Do not omit the `v` from the git tag.

For stable versions:

- MAJOR: intentional incompatible API changes.
- MINOR: backward-compatible features.
- PATCH: backward-compatible fixes.
- Prerelease: validation iterations before the stable release.

Do not infer a version bump from commit count alone. Base it on compatibility and release intent.

## Prepare a Release

Create a release branch from current `main`:

```bash
git switch main
git pull --ff-only
git switch -c release/<VERSION>
```

Update exactly these version sources:

- `VERSION`
- `lib/medusa/version.rb`
- `medusa.gemspec`

Move the relevant `CHANGELOG.md` entries out of `Unreleased` into a dated release section.

For a prerelease:

```markdown
## Unreleased

## Pre-release v2.0.0.pre.N (YYYY-MM-DD)
```

Keep the changelog focused on user-visible features, fixes, compatibility changes, dependency policy, and important release infrastructure changes. Do not dump commit history into it.

## Pre-PR Validation

Before opening the release PR, verify:

```bash
version="$(cat VERSION)"

ruby -Ilib -e '
  require "medusa/version"
  expected = File.read("VERSION").strip
  abort "VERSION mismatch" unless Medusa::VERSION == expected
'

ruby -e '
  expected = File.read("VERSION").strip
  spec = Gem::Specification.load("medusa.gemspec")
  abort "Unable to load medusa.gemspec" unless spec
  abort "gemspec mismatch" unless spec.version.to_s == expected
'

git diff --check
```

If dependencies are installed, also run:

```bash
BUNDLE_WITHOUT=debugging_tools bundle exec rspec spec
BUNDLE_WITHOUT=debugging_tools bundle exec rake docs:links
gem build medusa.gemspec
```

Do not commit generated `.gem` artifacts.

## Release PR

Prefer one small release-prep commit.

Typical title:

```
chore: prepare <VERSION>
```

The PR should state:

- the version being prepared;
- which release metadata files changed;
- the main changes included in the release;
- that no tag is created by the PR;
- the exact post-merge release sequence.

Do not tag from the release branch.

Do not create a GitHub Release from the release branch.

## CI Gate

The normal reusable release CI currently covers:

- RSpec on Ruby 3.3;
- RSpec on Ruby 3.4;
- RSpec on Ruby 4.0;
- minimum supported runtime dependencies;
- documentation links checked using Medusa;
- authenticated private-login smoke coverage.

The publishing workflow calls that full CI before publishing.

A green earlier commit is not enough. The exact release commit must be green.

## Tagging

After the release PR is merged, fetch the exact `main` merge commit and verify its version before tagging.

Example:

```bash
git switch main
git pull --ff-only

version="$(cat VERSION)"
test "$version" = "2.0.0.pre.N"

ruby -Ilib -e '
  require "medusa/version"
  expected = File.read("VERSION").strip
  abort unless Medusa::VERSION == expected
'

ruby -e '
  expected = File.read("VERSION").strip
  spec = Gem::Specification.load("medusa.gemspec")
  abort unless spec && spec.version.to_s == expected
'

tag="v$version"

git tag -a "$tag" -m "Medusa $tag"
git show "$tag"
git push origin "$tag"
```

Before pushing, explicitly inspect `git show "$tag"` and confirm:

- the tag name starts with `v`;
- the commit is the intended current `main` commit;
- all three version sources at that commit match the tag after removing the leading `v`.

Never force-move a published release tag.

## RubyGems Publishing

`.github/workflows/publish-gem.yml` is the canonical publishing path.

It:

1. runs the reusable full CI;
2. checks that the tag version matches the gemspec version;
3. publishes through RubyGems Trusted Publishing.

Do not manually run `gem push` unless explicitly recovering from a documented CI infrastructure failure and the maintainer has chosen that recovery path.

After pushing the tag:

- inspect the `Publish gem` workflow;
- confirm the CI job succeeded;
- confirm `Verify tag matches gem version` succeeded;
- confirm the RubyGems release step succeeded;
- verify the version exists on RubyGems.

If the tag-version check fails, stop. Do not create a GitHub Release.

## GitHub Release

Create the GitHub Release only after RubyGems shows the new version.

Use:

- tag: exactly `v<VERSION>`;
- title: `v<VERSION> — <short highlight>`;
- prerelease: enabled for `.pre.N` versions;
- concise notes summarizing the important user-visible changes;
- a full changelog link from the previous valid release tag.

Do not create a second differently named tag just to satisfy the GitHub UI.

Because releases are immutable, double-check the tag and title before publishing.

## Failure Recovery

### Wrong tag, no GitHub Release, no RubyGems publish

If a tag was created incorrectly but no immutable GitHub Release exists and nothing was published to RubyGems:

1. stop the workflow;
2. determine whether the tag can safely be deleted;
3. delete the bad tag if appropriate;
4. fix release metadata;
5. recreate the correct tag from the correct commit.

Do not guess. Verify remote state first.

### Immutable GitHub Release created incorrectly

Treat that release version/tag name as burned.

Do not attempt to recycle the version.

Prepare the next version, for example:

```
2.0.0.pre.3 -> 2.0.0.pre.4
```

Document the correction in the release-prep PR when useful.

### RubyGems version published incorrectly

RubyGems versions are immutable.

Do not overwrite the version. If necessary, yank it and release a new version with the correction.

Prefer a forward fix over history rewriting.

### Release contains a code regression

Do not delete history to hide the release.

Prepare the next patch/prerelease with the fix, document the regression if material, and release normally.

## Final Release Checklist

Before tagging:

- [ ] Release PR merged into `main`
- [ ] `VERSION` matches intended version
- [ ] `Medusa::VERSION` matches
- [ ] gemspec version matches
- [ ] CHANGELOG section is correct
- [ ] exact merge commit CI is green
- [ ] tag will be `v<VERSION>`
- [ ] tag points to exact merged `main` commit

After tagging:

- [ ] `Publish gem` workflow triggered
- [ ] full release CI passed
- [ ] tag/version verification passed
- [ ] RubyGems publishing passed
- [ ] version is visible on RubyGems
- [ ] GitHub Release created last
- [ ] GitHub Release uses `v<VERSION>`
- [ ] prerelease flag is correct
- [ ] changelog comparison link uses valid release tags

## Release Notes Style

Keep release notes short.

For a meaningful prerelease, prefer:

```markdown
Medusa 2.0 prerelease with two major runtime improvements:

- <major feature>
- <major feature>

Also includes <secondary improvements>.

Supports Ruby 3.3, 3.4, and 4.0.

**Full Changelog:** <previous-tag>...<current-tag>
```

Do not duplicate the entire changelog.

## Principle

The release commit, tag, RubyGems version, and GitHub Release are four representations of the same release.

Do not create the next representation until the previous one has been verified.

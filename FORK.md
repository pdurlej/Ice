# About this fork

This is an **AI-native** maintained continuation of [jordanbaird/Ice](https://github.com/jordanbaird/Ice).
Upstream's last code commit was 2025-06-06 and the last stable release
(0.11.12) shipped 2024-10-29 - before macOS Sequoia and Tahoe. This fork
picks up the open community PRs that already exist upstream, ships them
as proper releases, and layers AI integration (MCP server) on top.

## Positioning vs sibling forks

Multiple maintained forks of Ice exist - that is healthy for the ecosystem.

- **[stonerl/Thaw](https://github.com/stonerl/Thaw)** is the established maintenance fork: 6,000+ stars, active release cadence, focused purely on Tahoe stability. **Choose Thaw** if you want a drop-in Ice replacement without AI surface area.
- **Fire (this repo)** is the *AI-native* fork. Differentiator: an embedded MCP server (Model Context Protocol) so Claude, Cursor, and Codex can read and (in fire.7+) modify the menu bar layout. **Choose Fire** if you want to experiment with AI-assisted menu bar management - and you don't mind being on the leading edge.
- **upstream [jordanbaird/Ice](https://github.com/jordanbaird/Ice)** remains the canonical project. Both Thaw and Fire honor that work and remain GPL-3.0. Bugs that exist upstream should be filed upstream first.

Fire is maintained by a non-developer running product / vision, with Claude (Anthropic's AI) as the implementation collaborator. That is the experiment: keeping useful software alive when the human-only maintainer cohort is not large enough to staff every project the community depends on. If experiments here produce something generally useful (e.g., the MCP integration layer), the intent is to send it upstream or to Thaw as a PR - same north star, different surface area.

## Branch genealogy (why fire/main is based on upstream `macos-26`)

Upstream has four meaningful branches:

- `main` - abandoned for code in June 2025. Last two commits are issue
  template edits. **Does not work on macOS 26 Tahoe.**
- `0.12.0` - next-release prep: 37 commits of refactoring, full-screen
  search panel, utility window mask. Independent of Tahoe work.
- `macos-26` - Tahoe compatibility: HIDEventManager rename, screen
  capture rework, version bumps. 75 commits ahead of main. This is
  where the only Tahoe pre-release tag (`0.11.13-dev.2`, 2025-09-16)
  lives, and every open community PR that fixes a Tahoe bug is based
  here, not on main.
- `profiles` - feature branch for layout profiles (issue #26). Based on
  `0.12.0`. Incomplete.

`macos-26` and `0.12.0` diverged early and were never merged together,
so they are independent forks of upstream's history. Picking one as the
base for fire/main is therefore a real choice, not a formality.

**fire/main is based on `macos-26`.** Reasons:

1. The only Tahoe-capable build (`0.11.13-dev.2`) ships from here.
2. Every Tahoe-related community PR was opened against this branch.
   Cherry-picking them onto `main` fails - the surrounding code has
   moved.
3. The 37 commits in `0.12.0` are real value (search panel UX, several
   refactors) but can be merged into fire/main as a separate batch
   later; they are not blockers for shipping a Tahoe stable.
4. `main` is only 2 commits ahead of `macos-26`, and both are issue
   template edits we will overwrite with our own templates anyway.

## Local repo conventions

- `main` mirrors `jordanbaird/Ice:main`; only fast-forwards from
  upstream. Kept around so we can diff against the abandoned line.
- `fire/main` is the maintained fork, based on `upstream/macos-26`.
  All work goes here.
- `merge/pr-NNNN-short-description` are per-PR working branches that
  get cherry-picked or merged into `fire/main`.

## Remotes

```
origin    https://github.com/pdurlej/fire-from-ice         # the fork (push)
upstream  https://github.com/jordanbaird/Ice     # original (read-only)
```

## Phasing

1. **Tahoe stability.** Cherry-pick the open community PRs that fix
   macOS 26 issues on top of the `macos-26` baseline. Ship as
   `0.11.13-fire.1` under the existing `com.jordanbaird.Ice` bundle ID
   so current users upgrade in place with no migration.
2. **0.12.0 merge.** Pull in the 37 refactor/search-panel commits from
   `upstream/0.12.0`. Resolve conflicts against the macos-26 baseline.
   Ship as `0.12.0-fire.1`.
3. **Feature merges.** Per-display configuration (upstream #612), auto
   Ice Bar by screen width (#795), notch-aware auto-hide (#941),
   multimonitor single space fix (#667).
4. **Rebrand to Fire.** New bundle ID, new icon, first-launch migration
   that copies `UserDefaults` and Keychain entries from the old
   `com.jordanbaird.Ice` domain. TCC permissions (Accessibility, Screen
   Recording) must be re-granted because TCC keys on bundle ID - this
   is a one-time UX cost documented in the migration flow.
5. **Original features for heavy users.** Profiles for menu-bar layout
   (#26) - start from `upstream/profiles` if it is salvageable, otherwise
   from scratch. Trigger conditions (#62). Sensible defaults for
   new-icon placement (#6). Config export/import (#326). Investigation
   of the recurring "Layout settings is empty" class of bugs (#744,
   #891).

## Attribution and license

All code remains under GPL-3.0, unchanged. Jordan Baird remains the
original author and copyright holder. This fork is independent and
unofficial - please do not file fork-specific issues on the upstream
tracker.

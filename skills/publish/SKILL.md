---
name: publish
description: "Publish a release by running `just publish`. Use when the user says '/publish', 'publish release', 'cut a release', 'release', 'tag and release', or wants to build, tag, and publish a new version."
---

# Publish

Publish a release by running `just publish`.

## Instructions

1. **Verify justfile exists** — look for a `justfile` in the project root.

2. **If no justfile found**, stop and tell the user:

   ```
   No justfile found in the project root.

   This skill requires a justfile with a `publish` recipe. Install the justfile skill and generate one:

     npx skills add agoodway/GoodSkills --skill justfile -g

   Then run:

     /justfile

   This will detect your project type and generate a justfile with build and release recipes.
   ```

3. **If justfile exists but has no `publish` recipe**, stop and tell the user:

   ```
   Your justfile does not have a `publish` recipe.

   Add a publish recipe to your justfile. Example:

     publish: test dist checksums
         git tag -a "v{{version}}" -m "v{{version}}"
         git push origin "v{{version}}"
         gh release create "v{{version}}" dist/* --title "v{{version}}" --generate-notes
   ```

4. **If justfile exists with a `publish` recipe**, confirm with the user before running:
   - Show the current version (check `build.zig.zon`, `mix.exs`, `package.json`, `Cargo.toml`, or `justfile` version variable)
   - Ask: "Ready to publish v{version}? This will run tests, build release artifacts, tag, push, and create a GitHub release."
   - If the user confirms, run `just publish` and report the results.
   - If the user wants to bump the version first, suggest `just bump` (or `just bump minor` / `just bump major`).

5. If the publish command fails:
   - Show the full output so the user can see what failed.
   - Common failures: tests failing, missing `gh` CLI, not authenticated with GitHub, dirty working tree.

$ARGUMENTS

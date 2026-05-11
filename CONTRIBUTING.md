# Contributing

Thanks for your interest. This project is small and the bar for changes is
"makes the image more useful or more secure without making it bigger or
weirder."

## Ground rules

- Apache-2.0 license — by contributing you agree your work is licensed under it.
- One topic per PR. A 50-line PR that does one thing well lands faster than
  a 500-line PR that does six.
- Keep the image lean. New runtime apt packages need a justification in
  the PR description.
- Don't add new env vars without documenting them in `.env.example` **and**
  `README.md`.

## Dev loop

```bash
./build.sh                           # full source build (~10-30 min)
docker compose --profile host up -d  # run it
docker exec -it freeswitch fs_cli    # poke around

# lint locally (CI runs these too)
docker run --rm -i hadolint/hadolint < Dockerfile
docker run --rm -v "$PWD:/mnt" koalaman/shellcheck:stable /mnt/scripts/*.sh /mnt/build.sh
```

## Testing changes

The CI build verifies the image compiles and `freeswitch -version` runs.
For changes that affect runtime behaviour (entrypoint logic, config
injection, module selection) please describe in the PR how you verified —
ideally a `fs_cli` transcript or `docker logs` excerpt.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/) prefixes:

- `feat:` new capability
- `fix:` bug fix
- `docs:` README / docs only
- `build:` Dockerfile / CI changes
- `refactor:` no functional change
- `chore:` housekeeping

Example: `feat(entrypoint): randomize ESL password on first start`.

## Releasing

Maintainers tag with `vX.Y.Z` matching the FreeSWITCH minor (e.g.
`v1.10.11-1` for the first release tracking FS 1.10.11). The
`release.yml` workflow builds and pushes multi-arch images to Docker Hub.

The `CHANGELOG.md` is updated as part of the release PR.

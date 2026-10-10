# devbord release action

A GitHub Action that tells devbord about a build: it creates the release with its commit, uploads source maps and the
symbols of native libraries, and reports the deploy. Stack traces of that release are then readable, issues show the
commit that most likely caused them, and "resolved in the next release" knows what the next release is.

## Use

```yaml
- uses: actions/checkout@v4
- run: npm ci && npm run build

- uses: devbord-com/release-action@v1
  with:
    project: 12
    api-key: ${{ secrets.DEVBORD_KEY }}
    release: my-app@${{ github.sha }}
    sourcemaps: dist/assets
    prefix: ~/assets
    deploy: production
```

`release` must be the exact value the app sends with its errors.

## Inputs

| Input | Default | What it is |
|---|---|---|
| `project` | | Number of the project: the last part of the DSN. |
| `api-key` | | API key of the board with write access (board menu › Integrations › API keys). Pass it from a secret. |
| `release` | | Version of this build. |
| `url` | `https://devbord.com` | Address of devbord, for a self-hosted one. |
| `commit` | the commit of the workflow run | Commit of this build. |
| `sourcemaps` | | Folder that is searched for `.map` files, subfolders included. Empty: none are uploaded. |
| `prefix` | `~/` | Path the files are served from. `~/assets` when `dist/assets/app.js` is at `https://your.site/assets/app.js`. |
| `symbols` | | Native libraries with debug symbols (`.so` before `strip`, or `.dSYM` folders), one per line. |
| `deploy` | | Environment to report a deploy for. Empty: no deploy is reported. |

With only `project`, `api-key` and `release` the action creates the release and nothing else, which is enough for
games and servers without source maps.

## Notes

- The step fails when devbord refuses an upload, so a build without readable stack traces does not go out unnoticed.
- Uploading symbols needs `nm` on the runner, and `dwarfdump` (macOS) or `readelf` (Linux) to read the build ID.
- The API needs the Premium plan.

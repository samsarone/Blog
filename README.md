# Samsar Blog

Minimal Ghost fork for the Samsar blog deployment.

## What is kept

- `ghost/core`: Ghost server runtime and content
- `ghost/admin`: Ghost admin source/assets
- `ghost/i18n`: workspace package required by Ghost core
- `ghost/parse-email-address`: workspace package required by Ghost core
- custom Samsar integration and `samsar` theme under `ghost/core`

## What was removed

- monorepo tooling and CI metadata
- docs, apps, e2e, scripts, and editor-specific folders
- test suites and several dev-only config files

## Local install

```bash
pnpm run install:blog
API_KEY=your_key API_HOST=https://api.samsar.one/v1 pnpm start
```

## Production

Use:

- `API_KEY` from environment
- `API_HOST=https://api.samsar.one/v1`
- Ghost URL `https://samsar.one/blog/`

See [BLOG_SETUP.md](/Users/pritamroy/Documents/others/workspace/samsar_one/samsar_blog/BLOG_SETUP.md).

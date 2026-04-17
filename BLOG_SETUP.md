# Samsar Blog Setup

## Runtime

- Ghost canonical URL should be `https://samsar.one/blog/`
- Keep `API_HOST=https://api.samsar.one/v1`
- Set `API_KEY` in the Ghost runtime environment

## Theme

- Activate the `samsar` theme from `ghost/core/content/themes/samsar`
- The theme includes a landing-style home page and a built-in text enhancement widget
- The widget posts to `POST /members/api/samsar/enhance-text`

## CloudFront and S3 split

`landing` remains the S3 static origin for the main site, but `/blog` cannot be served from S3 because Ghost is dynamic.

Configure CloudFront so:

- default behavior points to the existing `landing` S3 origin
- `/blog` points to the Ghost origin
- `/blog/*` points to the Ghost origin

The Ghost origin should receive the request path unchanged so the site URL subdirectory stays `/blog`.

## Landing links

All public blog links in `landing` should use `https://samsar.one/blog`.

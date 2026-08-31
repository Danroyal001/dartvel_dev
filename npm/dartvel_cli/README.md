# dartvel_cli

An alias for [`dartvel_dev`](https://www.npmjs.com/package/dartvel_dev).

```bash
npm i -g dartvel_cli   # or: npm i -g dartvel_dev
dartvel --help
```

Both install the same CLI. The package is `dartvel_cli` on pub.dev and
`dartvel_dev` on npm, because `dartvel` was already taken on pub.dev by an
unrelated package — so whichever name you reach for, it works.

This package contains no implementation. It depends on `dartvel_dev` and
forwards to it, rather than carrying a second copy of the launcher that would
have to be kept in step.

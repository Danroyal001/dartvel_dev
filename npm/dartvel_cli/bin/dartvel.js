#!/usr/bin/env node

'use strict';

// dartvel_cli is an alias for dartvel_dev.
//
// The CLI is published on pub.dev as dartvel_cli and on npm as dartvel_dev,
// because `dartvel` was already taken on pub.dev by an unrelated package. That
// left `npm i -g dartvel_cli` installing nothing, which is the name people
// reach for first. This package exists so both work and resolve to one
// implementation -- a second copy of the launcher would be a second thing to
// keep in step.

const { run } = require('dartvel_dev');

run(process.argv.slice(2))
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error('Error running dartvel:', error.message);
    process.exit(1);
  });

#!/usr/bin/env node

'use strict';

const { run } = require('../index');

run(process.argv.slice(2))
  .then((code) => process.exit(code))
  .catch((error) => {
    console.error('Error running dartvel:', error.message);
    process.exit(1);
  });

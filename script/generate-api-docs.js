#!/usr/bin/env node

const joanna = require('joanna')
const tello = require('tello')
const glob = require('glob')
const fs = require('fs')

// Change to src/**/*.js when https://github.com/atom/joanna/issues/5 is fixed
const metadata = joanna(glob.sync(`src/**/!(scope-selector-matchers).js`))
fs.writeFileSync('api.json', tello.digest(metadata))

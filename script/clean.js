#!/usr/bin/env node

const rimraf = require('rimraf')

rimraf.sync('lib')
rimraf.sync('api.json')

#!/usr/bin/env node

const path = require('path')
const fs = require('fs-plus')
const GrammarRegistry = require('../lib/grammar-registry')

const registry = new GrammarRegistry()
const jsGrammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'javascript.json'))
jsGrammar.maxTokensPerLine = Infinity
const cssGrammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'css.json'))
cssGrammar.maxTokensPerLine = Infinity

function tokenize (grammar, content, lineCount) {
  const start = Date.now()
  const tokenizedLines = grammar.tokenizeLines(content, false)
  const duration = Date.now() - start
  let tokenCount = 0
  for (let tokenizedLine of tokenizedLines) {
    tokenCount += tokenizedLine.length
  }
  const tokensPerMillisecond = Math.round(tokenCount / duration)
  console.log(`Generated ${tokenCount} tokens for ${lineCount} lines in ${duration}ms (${tokensPerMillisecond} tokens/ms)`)
};

function tokenizeFile (filePath, grammar, message) {
  console.log()
  console.log(message)
  const content = fs.readFileSync(filePath, 'utf8')
  const lineCount = content.split('\n').length
  tokenize(grammar, content, lineCount)
};

tokenizeFile(path.join(__dirname, 'fixtures', 'jquery.js'), jsGrammar, 'Tokenizing jQuery v2.0.3')
tokenizeFile(path.join(__dirname, 'fixtures', 'jquery.min.js'), jsGrammar, 'Tokenizing jQuery v2.0.3 minified')
tokenizeFile(path.join(__dirname, 'fixtures', 'bootstrap.css'), cssGrammar, 'Tokenizing Bootstrap CSS v3.1.1')
tokenizeFile(path.join(__dirname, 'fixtures', 'bootstrap.min.css'), cssGrammar, 'Tokenizing Bootstrap CSS v3.1.1 minified')

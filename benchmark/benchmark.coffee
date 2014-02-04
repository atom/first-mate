path = require 'path'
fs = require 'fs-plus'
GrammarRegistry = require '../lib/grammar-registry'

console.log 'Tokenizing jQuery v2.0.3'
registry = new GrammarRegistry()
grammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'javascript.json'))
content = fs.readFileSync(path.join(__dirname, 'large.js'), 'utf8')
lineCount = content.split('\n').length

for i in [0...1]
  start = Date.now()
  tokens = grammar.tokenizeLines(content)
  duration = Date.now() - start
  tokenCount = tokens.reduce ((count, line) -> count + line.length), 0
  tokensPerMillisecond = Math.round(tokenCount / duration)
  console.log "Generated #{tokenCount} tokens for #{lineCount} lines in #{duration}ms (#{tokensPerMillisecond} tokens/ms)"

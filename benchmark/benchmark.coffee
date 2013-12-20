path = require 'path'
fs = require 'fs-plus'
Registry = require '../src/registry'

registry = new Registry()
grammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'javascript.json'))
content = fs.readFileSync(path.join(__dirname, 'large.js'), 'utf8')
lineCount = content.split('\n').length

for i in [0...1]
  start = Date.now()
  tokens = grammar.tokenizeLines(content)
  duration = Date.now() - start
  tokenCount = tokens.reduce ((count, line) -> count + line.length), 0
  console.log "Generated #{tokenCount} tokens for #{lineCount} lines in #{duration}ms"

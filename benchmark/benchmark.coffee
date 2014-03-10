path = require 'path'
fs = require 'fs-plus'
GrammarRegistry = require '../lib/grammar-registry'

registry = new GrammarRegistry()
grammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'javascript.json'))

tokenize = (grammar, content, lineCount) ->
  start = Date.now()
  tokens = grammar.tokenizeLines(content)
  duration = Date.now() - start
  tokenCount = tokens.reduce ((count, line) -> count + line.length), 0
  tokensPerMillisecond = Math.round(tokenCount / duration)
  console.log "Generated #{tokenCount} tokens for #{lineCount} lines in #{duration}ms (#{tokensPerMillisecond} tokens/ms)"

console.log 'Tokenizing jQuery v2.0.3'
content = fs.readFileSync(path.join(__dirname, 'large.js'), 'utf8')
lineCount = content.split('\n').length
tokenize(grammar, content, lineCount)

console.log()

console.log 'Tokenizing jQuery v2.0.3 minified'
content = fs.readFileSync(path.join(__dirname, 'large.min.js'), 'utf8')
lineCount = content.split('\n').length
tokenize(grammar, content, lineCount)

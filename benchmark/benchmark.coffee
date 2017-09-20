path = require 'path'
fs = require 'fs-plus'
GrammarRegistry = require '../src/grammar-registry'

registry = new GrammarRegistry()
jsGrammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'javascript.json'))
jsGrammar.maxTokensPerLine = Infinity
cssGrammar = registry.loadGrammarSync(path.resolve(__dirname, '..', 'spec', 'fixtures', 'css.cson'))
cssGrammar.maxTokensPerLine = Infinity

tokenize = (grammar, content, lineCount) ->
  start = Date.now()
  tokenizedLines = grammar.tokenizeLines(content, false)
  duration = Date.now() - start
  tokenCount = 0
  for tokenizedLine in tokenizedLines
    tokenCount += tokenizedLine.length
  tokensPerMillisecond = Math.round(tokenCount / duration)
  console.log "Generated #{tokenCount} tokens for #{lineCount} lines in #{duration}ms (#{tokensPerMillisecond} tokens/ms)"

tokenizeFile = (filePath, grammar, message) ->
  console.log()
  console.log(message)
  content = fs.readFileSync(filePath, 'utf8')
  lineCount = content.split('\n').length
  tokenize(grammar, content, lineCount)

tokenizeFile(path.join(__dirname, 'large.js'), jsGrammar, 'Tokenizing jQuery v2.0.3')
tokenizeFile(path.join(__dirname, 'large.min.js'), jsGrammar, 'Tokenizing jQuery v2.0.3 minified')
tokenizeFile(path.join(__dirname, 'bootstrap.css'), cssGrammar, 'Tokenizing Bootstrap CSS v3.1.1')
tokenizeFile(path.join(__dirname, 'bootstrap.min.css'), cssGrammar, 'Tokenizing Bootstrap CSS v3.1.1 minified')

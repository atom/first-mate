fs = require 'fs'

PEG = require 'pegjs'

parser = null

createParser = ->
  unless parser?
    matchersPath = require.resolve('./scope-selector-matchers')
    matchers = "{ var matchers= require('#{matchersPath}'); }"
    patternPath = require.resolve('./scope-selector-pattern.pegjs')
    patternContents = "#{matchers}\n#{fs.readFileSync(patternPath, 'utf8')}"
    parser = PEG.buildParser(patternContents)
  parser

module.exports =
class ScopeSelector

  constructor: (source) -> @matcher = createParser().parse(source)

  matches: (scopes) -> @matcher.matches(scopes)

  toCssSelector: -> @matcher.toCssSelector()

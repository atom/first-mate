fs = require 'fs'
path = require 'path'
PEG = require 'pegjs'

parser = null

createParser = ->
  unless parser?
    matchersPath = require.resolve('./scope-selector-matchers')
    matchersPath = matchersPath.replace(/\\/g, '\\\\')  if path.sep is '\\'
    matchers = "{ var matchers= require('#{matchersPath}'); }"
    patternPath = require.resolve('../grammars/scope-selector-pattern.pegjs')
    patternContents = "#{matchers}\n#{fs.readFileSync(patternPath, 'utf8')}"
    parser = PEG.buildParser(patternContents)
  parser

module.exports =
class ScopeSelector

  # Create a new scope selector.
  #
  # source - A {String} to parse as a scope selector.
  constructor: (source) -> @matcher = createParser().parse(source)

  # Check if this scope selector matches the scopes.
  #
  # scopes - An {Array} of {String}s.
  #
  # Returns a {Boolean}.
  matches: (scopes) -> @matcher.matches(scopes)

  # Convert this TextMate scope selector to a CSS selector.
  #
  # Returns a {String}.
  toCssSelector: -> @matcher.toCssSelector()

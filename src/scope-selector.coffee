ScopeSelectorParser = require '../lib/scope-selector-parser'

module.exports =
class ScopeSelector
  # Create a new scope selector.
  #
  # source - A {String} to parse as a scope selector.
  constructor: (source) -> @matcher = ScopeSelectorParser.parse(source)

  # Check if this scope selector matches the scopes.
  #
  # scopes - An {Array} of {String}s or a single {String}.
  #
  # Returns a {Boolean}.
  matches: (scopes) ->
    scopes = [scopes] if typeof scopes is 'string'
    @matcher.matches(scopes)

  # Gets the prefix of this scope selector.
  #
  # scopes - An {Array} of {String}s or a single {String}.
  #
  # Returns a {String} if there is a prefix or undefined otherwise.
  getPrefix: (scopes) ->
    scopes = [scopes] if typeof scopes is 'string'
    @matcher.getPrefix(scopes)

  # Convert this TextMate scope selector to a CSS selector.
  #
  # Returns a {String}.
  toCssSelector: -> @matcher.toCssSelector()

  # Convert this TextMate scope selector to a CSS selector, prefixing scopes with `syntax--`.
  #
  # Returns a {String}.
  toCssSyntaxSelector: -> @matcher.toCssSyntaxSelector()

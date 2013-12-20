_ = require 'underscore-plus'
{OnigScanner} = require 'oniguruma'

Pattern = require './pattern'
ScopeSelector = require './scope-selector'

module.exports =
class Injections
  constructor: (@grammar, injections={}) ->
    @injections = []
    @scanners = {}
    for selector, values of injections
      continue unless values?.patterns?.length > 0
      patterns = []
      anchored = false
      for regex in values.patterns
        pattern = @grammar.createPattern({regex})
        anchored = true if pattern.anchored
        patterns.push(pattern.getIncludedPatterns(grammar, patterns)...)
      @injections.push
        anchored: anchored
        selector: new ScopeSelector(selector)
        patterns: patterns

  getScanner: (injection, firstLine, position, anchorPosition) ->
    return injection.scanner if injection.scanner?

    regexes = _.map injection.patterns, (pattern) ->
      pattern.getRegex(firstLine, position, anchorPosition)
    scanner = new OnigScanner(regexes)
    scanner.patterns = injection.patterns
    scanner.anchored = injection.anchored
    injection.scanner = scanner unless scanner.anchored
    scanner

  getScanners: (ruleStack, firstLine, position, anchorPosition) ->
    scanners = []
    scopes = @grammar.scopesFromStack(ruleStack)
    for injection in @injections
      if injection.selector.matches(scopes)
        scanner = @getScanner(injection, firstLine, position, anchorPosition)
        scanners.push(scanner)
    scanners

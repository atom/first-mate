_ = require 'underscore-plus'
{OnigScanner} = require 'oniguruma'

module.exports =
class Rule
  constructor: (@grammar, @registry, {@scopeName, patterns, @endPattern}={}) ->
    patterns ?= []
    @patterns = patterns.map (pattern) => @grammar.createPattern(pattern)
    if @endPattern and not @endPattern.hasBackReferences
      @patterns.unshift(@endPattern)
    @scannersByBaseGrammarName = {}
    @createEndPattern = null
    @anchorPosition = -1

  getIncludedPatterns: (baseGrammar, included=[]) ->
    return [] if _.include(included, this)

    included = included.concat([this])
    allPatterns = []
    for pattern in @patterns
      allPatterns.push(pattern.getIncludedPatterns(baseGrammar, included)...)
    allPatterns

  clearAnchorPosition: -> @anchorPosition = -1

  createScanner: (patterns, firstLine, position) ->
    anchored = false
    regexes = _.map patterns, (pattern) =>
      anchored = true if pattern.anchored
      pattern.getRegex(firstLine, position, @anchorPosition)

    scanner = new OnigScanner(regexes)
    scanner.patterns = patterns
    scanner.anchored = anchored
    scanner

  getScanner: (baseGrammar, position, firstLine) ->
    return scanner if scanner = @scannersByBaseGrammarName[baseGrammar.name]

    patterns = @getIncludedPatterns(baseGrammar)
    scanner = @createScanner(patterns, firstLine, position)
    @scannersByBaseGrammarName[baseGrammar.name] = scanner unless scanner.anchored
    scanner

  scanInjections: (ruleStack, line, position, firstLine) ->
    baseGrammar = ruleStack[0].grammar
    if injections = baseGrammar.injections
      scanners = injections.getScanners(ruleStack, position, firstLine, @anchorPosition)
      for scanner in scanners
        result = scanner.findNextMatch(line, position)
        return result if result?

  normalizeCaptureIndices: (line, captureIndices) ->
    lineLength = line.length
    captureIndices.forEach (capture) ->
      capture.end = Math.min(capture.end, lineLength)
      capture.start = Math.min(capture.start, lineLength)

  findNextMatch: (ruleStack, line, position, firstLine) ->
    lineWithNewline = "#{line}\n"
    baseGrammar = ruleStack[0].grammar
    results = []

    scanner = @getScanner(baseGrammar, position, firstLine)
    if result = scanner.findNextMatch(lineWithNewline, position)
      results.push(result)

    if result = @scanInjections(ruleStack, lineWithNewline, position, firstLine)
      results.push(result)

    scopes = @grammar.scopesFromStack(ruleStack)
    for injectionGrammar in _.without(@registry.injectionGrammars, @grammar, baseGrammar)
      if injectionGrammar.injectionSelector.matches(scopes)
        scanner = injectionGrammar.getInitialRule().getScanner(injectionGrammar, position, firstLine)
        if result = scanner.findNextMatch(lineWithNewline, position)
          results.push(result)

    if results.length > 0
      _.min results, (result) =>
        @normalizeCaptureIndices(line, result.captureIndices)
        result.captureIndices[0].start

  getNextTokens: (ruleStack, line, position, firstLine) ->
    result = @findNextMatch(ruleStack, line, position, firstLine)
    return null unless result?

    { index, captureIndices, scanner } = result
    firstCapture = captureIndices[0]
    nextTokens = scanner.patterns[index].handleMatch(ruleStack, line, captureIndices)
    { nextTokens, tokensStartPosition: firstCapture.start, tokensEndPosition: firstCapture.end }

  getRuleToPush: (line, beginPatternCaptureIndices) ->
    if @endPattern.hasBackReferences
      rule = @grammar.createRule({@scopeName})
      rule.endPattern = @endPattern.resolveBackReferences(line, beginPatternCaptureIndices)
      rule.patterns = [rule.endPattern, @patterns...]
      rule
    else
      this

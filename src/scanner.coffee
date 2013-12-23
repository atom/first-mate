{OnigScanner} = require 'oniguruma'

# Wrapper class for {OnigScanner} that caches them based on the presence of any
# anchor characters that change based on the current position being scanned.
#
# See {Pattern.replaceAnchor} for more details.
module.exports =
class Scanner
  constructor: (@patterns=[]) ->
    @anchored = false
    for pattern in @patterns when pattern.anchored
      @anchored = true
      break

    @anchoredScanner = null
    @firstLineAnchoredScanner = null
    @firstLineScanner = null
    @scanner = null

  createScanner: (firstLine, position, anchorPosition) ->
    patterns = @patterns.map (pattern) ->
      pattern.getRegex(firstLine, position, anchorPosition)
    scanner = new OnigScanner(patterns)

  getScanner: (firstLine, position, anchorPosition) ->
    unless @anchored
      @scanner ?= @createScanner(firstLine, position, anchorPosition)
      return @scanner

    if firstLine
      if position is anchorPosition
        @firstLineAnchoredScanner ?= @createScanner(firstLine, position, anchorPosition)
      else
        @firstLineScanner ?= @createScanner(firstLine, position, anchorPosition)
    else if position is anchorPosition
      @anchoredScanner ?= @createScanner(firstLine, position, anchorPosition)
    else
      @scanner ?= @createScanner(firstLine, position, anchorPosition)

  findNextMatch: (line, firstLine, position, anchorPosition) ->
    scanner = @getScanner(firstLine, position, anchorPosition)
    match = scanner.findNextMatch(line, position)
    match?.scanner = this
    match

  handleMatch: (match, stack, line) ->
    pattern = @patterns[match.index]
    pattern.handleMatch(stack, line, match.captureIndices)

module.exports =
class Pattern
  constructor: ({@grammar, @registry, name, contentName, @include, match, begin, end, captures, beginCaptures, endCaptures, patterns, @popRule, @hasBackReferences}) ->
    @pushRule = null
    @capture = null
    @backReferences = null
    @scopeName = name ? contentName # TODO: We need special treatment of contentName

    if match
      if (end or @popRule) and @hasBackReferences ?= /\\\d+/.test(match)
        @match = match
      else
        @regexSource = match
      @captures = captures
    else if begin
      @regexSource = begin
      @captures = beginCaptures ? captures
      endPattern = new Pattern({@grammar, match: end, captures: endCaptures ? captures, popRule: true})
      @pushRule = new Rule({@grammar, @scopeName, patterns, endPattern})

    if @captures?
      for group, capture of @captures
        if capture.patterns?.length > 0 and not capture.rule
          capture.scopeName = @scopeName
          capture.rule = new Rule({@grammar})

    @anchored = @hasAnchor()

  getRegex: (firstLine, position, anchorPosition) ->
    if @anchored
      @replaceAnchor(firstLine, position, anchorPosition)
    else
      @regexSource

  hasAnchor: ->
    return false unless @regexSource
    escape = false
    for character in @regexSource.split('')
      return true if escape and 'AGz'.indexOf(character) isnt -1
      escape = not escape and character is '\\'
    false

  replaceAnchor: (firstLine, offset, anchor) ->
    escaped = []
    placeholder = '\uFFFF'
    escape = false
    for character in @regexSource.split('')
      if escape
        switch character
          when 'A'
            if firstLine
              escaped.push("\\#{character}")
            else
              escaped.push(placeholder)
          when 'G'
            if offset is anchor
              escaped.push("\\#{character}")
            else
              escaped.push(placeholder)
          when 'z' then escaped.push('$(?!\n)(?<!\n)')
          else escaped.push("\\#{character}")
        escape = false
      else if character is '\\'
        escape = true
      else
        escaped.push(character)

    escaped.join('')

  resolveBackReferences: (line, beginCaptureIndices) ->
    beginCaptures = []

    for {start, end} in beginCaptureIndices
      beginCaptures.push line[start...end]

    resolvedMatch = @match.replace /\\\d+/g, (match) ->
      index = parseInt(match[1..])
      _.escapeRegExp(beginCaptures[index] ? "\\#{index}")

    new Pattern({@grammar, hasBackReferences: false, match: resolvedMatch, @captures, @popRule})

  ruleForInclude: (baseGrammar, name) ->
    if name[0] == "#"
      @grammar.getRepository()[name[1..]]
    else if name == "$self"
      @grammar.getInitialRule()
    else if name == "$base"
      baseGrammar.getInitialRule()
    else
      @grammar.addIncludedGrammarScope(name)
      @registry.grammarForScopeName(name)?.getInitialRule()

  getIncludedPatterns: (baseGrammar, included) ->
    if @include
      rule = @ruleForInclude(baseGrammar, @include)
      rule?.getIncludedPatterns(baseGrammar, included) ? []
    else
      [this]

  resolveScopeName: (line, captureIndices) ->
    resolvedScopeName = @scopeName.replace /\${(\d+):\/(downcase|upcase)}/, (match, index, command) ->
      capture = captureIndices[parseInt(index)]
      if capture?
        replacement = line.substring(capture.start, capture.end)
        switch command
          when 'downcase' then replacement.toLowerCase()
          when 'upcase' then replacement.toUpperCase()
          else replacement
      else
        match

    resolvedScopeName.replace /\$(\d+)/, (match, index) ->
      capture = captureIndices[parseInt(index)]
      if capture?
        line.substring(capture.start, capture.end)
      else
        match

  handleMatch: (stack, line, captureIndices) ->
    scopes = @grammar.scopesFromStack(stack)
    if @scopeName and not @popRule
      scopes.push(@resolveScopeName(line, captureIndices))

    if @captures
      tokens = @getTokensForCaptureIndices(line, _.clone(captureIndices), scopes, stack)
    else
      {start, end} = captureIndices[0]
      zeroLengthMatch = end == start
      if zeroLengthMatch
        tokens = []
      else
        tokens = [@grammar.createToken(line[start...end], scopes)]
    if @pushRule
      ruleToPush = @pushRule.getRuleToPush(line, captureIndices)
      ruleToPush.anchorPosition = captureIndices[0].end
      stack.push(ruleToPush)
    else if @popRule
      stack.pop()

    tokens

  getTokensForCaptureRule: (rule, line, captureStart, captureEnd, scopes, stack) ->
    captureText = line.substring(captureStart, captureEnd)
    {tokens} = rule.grammar.tokenizeLine(captureText, [stack..., rule])
    tokens

  getTokensForCaptureIndices: (line, captureIndices, scopes, stack) ->
    parentCapture = captureIndices.shift()

    tokens = []
    if scope = @captures[parentCapture.index]?.name
      scopes = scopes.concat(scope)

    if captureRule = @captures[parentCapture.index]?.rule
      captureTokens = @getTokensForCaptureRule(captureRule, line, parentCapture.start, parentCapture.end, scopes, stack)
      tokens.push(captureTokens...)
      # Consume child captures
      while captureIndices.length and captureIndices[0].start < parentCapture.end
        captureIndices.shift()
    else
      previousChildCaptureEnd = parentCapture.start
      while captureIndices.length and captureIndices[0].start < parentCapture.end
        childCapture = captureIndices[0]

        emptyCapture = childCapture.end - childCapture.start == 0
        captureHasNoScope = not @captures[childCapture.index]
        if emptyCapture or captureHasNoScope
          captureIndices.shift()
          continue

        if childCapture.start > previousChildCaptureEnd
          tokens.push(@grammar.createToken(line[previousChildCaptureEnd...childCapture.start], scopes))

        captureTokens = @getTokensForCaptureIndices(line, captureIndices, scopes, stack)
        tokens.push(captureTokens...)
        previousChildCaptureEnd = childCapture.end

      if parentCapture.end > previousChildCaptureEnd
        tokens.push(@grammar.createToken(line[previousChildCaptureEnd...parentCapture.end], scopes))

    tokens

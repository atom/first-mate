_ = require 'underscore-plus'

AllDigitsRegex = /\\\d+/g
CustomCaptureIndexRegex = /\$(\d+)|\${(\d+):\/(downcase|upcase)}/
DigitRegex = /\\\d+/

module.exports =
class Pattern
  constructor: (@grammar, @registry, options={}) ->
    {name, contentName, match, begin, end, patterns} = options
    {captures, beginCaptures, endCaptures, applyEndPatternLast} = options
    {@include, @popRule, @hasBackReferences} = options

    @pushRule = null
    @backReferences = null
    @scopeName = name
    @contentScopeName = contentName

    if match
      if (end or @popRule) and @hasBackReferences ?= DigitRegex.test(match)
        @match = match
      else
        @regexSource = match
      @captures = captures
    else if begin
      @regexSource = begin
      @captures = beginCaptures ? captures
      endPattern = @grammar.createPattern({match: end, captures: endCaptures ? captures, popRule: true})
      @pushRule = @grammar.createRule({@scopeName, @contentScopeName, patterns, endPattern, applyEndPatternLast})

    if @captures?
      for group, capture of @captures
        if capture.patterns?.length > 0 and not capture.rule
          capture.scopeName = @scopeName
          capture.rule = @grammar.createRule(capture)

    @anchored = @hasAnchor()

  getRegex: (firstLine, position, anchorPosition) ->
    if @anchored
      @replaceAnchor(firstLine, position, anchorPosition)
    else
      @regexSource

  hasAnchor: ->
    return false unless @regexSource
    escape = false
    for character in @regexSource
      return true if escape and character in ['A', 'G', 'z']
      escape = not escape and character is '\\'
    false

  replaceAnchor: (firstLine, offset, anchor) ->
    escaped = []
    placeholder = '\uFFFF'
    escape = false
    for character in @regexSource
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
          when 'z'
            escaped.push('$(?!\n)(?<!\n)')
          else
            escaped.push("\\#{character}")
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

    resolvedMatch = @match.replace AllDigitsRegex, (match) ->
      index = parseInt(match[1..])
      if beginCaptures[index]?
        _.escapeRegExp(beginCaptures[index])
      else
        "\\#{index}"

    @grammar.createPattern({hasBackReferences: false, match: resolvedMatch, @captures, @popRule})

  ruleForInclude: (baseGrammar, name) ->
    if name[0] is "#"
      @grammar.getRepository()[name[1..]]
    else if name is "$self"
      @grammar.getInitialRule()
    else if name is "$base"
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

  resolveScopeName: (scopeName, line, captureIndices) ->
    resolvedScopeName = scopeName.replace CustomCaptureIndexRegex, (match, index, commandIndex, command) ->
      capture = captureIndices[parseInt(index ? commandIndex)]
      if capture?
        replacement = line.substring(capture.start, capture.end)
        # Remove leading dots that would make the selector invalid
        replacement = replacement.substring(1) while replacement[0] is '.'
        switch command
          when 'downcase' then replacement.toLowerCase()
          when 'upcase'   then replacement.toUpperCase()
          else replacement
      else
        match

  handleMatch: (stack, line, captureIndices, rule, endPatternMatch) ->
    content = []

    if @popRule
      {contentScopeName} = _.last(stack)
      content.push(-@grammar.idForScope(contentScopeName)) if contentScopeName
    else if @scopeName
      scopeName = @resolveScopeName(@scopeName, line, captureIndices)
      content.push(@grammar.idForScope(scopeName))

    if @captures
      content.push(@contentForCaptureIndices(line, _.clone(captureIndices), captureIndices, stack)...)
    else
      {start, end} = captureIndices[0]
      content.push(line[start...end]) unless end is start

    if @pushRule
      ruleToPush = @pushRule.getRuleToPush(line, captureIndices)
      ruleToPush.anchorPosition = captureIndices[0].end
      stack.push(ruleToPush)
      {contentScopeName} = ruleToPush
      content.push(@grammar.idForScope(contentScopeName)) if contentScopeName
    else
      {scopeName} = stack.pop() if @popRule
      content.push(-@grammar.idForScope(scopeName)) if scopeName

    content

  contentForCaptureRule: (rule, line, captureStart, captureEnd, stack) ->
    captureText = line.substring(captureStart, captureEnd)
    {content} = rule.grammar.tokenizeLine(captureText, [stack..., rule])

    # For capture matches, remove empty content caused by newline matches
    content.filter (symbol) -> symbol isnt ''

  # Get the tokens for the capture indices.
  #
  # line - The string being tokenized.
  # currentCaptureIndices - The current array of capture indices being
  #                         processed into tokens. This method is called
  #                         recursively and this array will be modified inside
  #                         this method.
  # allCaptureIndices - The array of all capture indices, this array will not
  #                     be modified.
  # stack - An array of rules.
  #
  # Returns a non-null but possibly empty array of tokens
  contentForCaptureIndices: (line, currentCaptureIndices, allCaptureIndices, stack) ->
    parentCapture = currentCaptureIndices.shift()

    content = []
    if scope = @captures[parentCapture.index]?.name
      parentCaptureScope = @resolveScopeName(scope, line, allCaptureIndices)
      content.push(@grammar.idForScope(parentCaptureScope))

    if captureRule = @captures[parentCapture.index]?.rule
      captureContent = @contentForCaptureRule(captureRule, line, parentCapture.start, parentCapture.end, stack)
      content.push(captureContent...)
      # Consume child captures
      while currentCaptureIndices.length and currentCaptureIndices[0].start < parentCapture.end
        currentCaptureIndices.shift()
    else
      previousChildCaptureEnd = parentCapture.start
      while currentCaptureIndices.length and currentCaptureIndices[0].start < parentCapture.end
        childCapture = currentCaptureIndices[0]

        emptyCapture = childCapture.end - childCapture.start is 0
        captureHasNoScope = not @captures[childCapture.index]
        if emptyCapture or captureHasNoScope
          currentCaptureIndices.shift()
          continue

        if childCapture.start > previousChildCaptureEnd
          content.push(line[previousChildCaptureEnd...childCapture.start])

        captureContent = @contentForCaptureIndices(line, currentCaptureIndices, allCaptureIndices, stack)
        content.push(captureContent...)
        previousChildCaptureEnd = childCapture.end

      if parentCapture.end > previousChildCaptureEnd
        content.push(line[previousChildCaptureEnd...parentCapture.end])

    if parentCaptureScope
      if content.length > 1
        content.push(-@grammar.idForScope(parentCaptureScope))
      else
        content.pop()

    content

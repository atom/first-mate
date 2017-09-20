_ = require 'underscore-plus'

AllCustomCaptureIndicesRegex = /\$(\d+)|\${(\d+):\/(downcase|upcase)}/g
AllDigitsRegex = /\\\d+/g
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
      beginCaptures.push(line.substring(start, end))

    resolvedMatch = @match.replace AllDigitsRegex, (match) ->
      index = parseInt(match[1..])
      if beginCaptures[index]?
        _.escapeRegExp(beginCaptures[index])
      else
        "\\#{index}"

    @grammar.createPattern({hasBackReferences: false, match: resolvedMatch, @captures, @popRule})

  ruleForInclude: (baseGrammar, name) ->
    hashIndex = name.indexOf('#')
    if hashIndex is 0
      @grammar.getRepository()[name[1..]]
    else if hashIndex >= 1
      grammarName = name[0..hashIndex-1]
      ruleName = name[hashIndex+1..]
      @grammar.addIncludedGrammarScope(grammarName)
      @registry.grammarForScopeName(grammarName)?.getRepository()[ruleName]
    else if name is '$self'
      @grammar.getInitialRule()
    else if name is '$base'
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
    resolvedScopeName = scopeName.replace AllCustomCaptureIndicesRegex, (match, index, commandIndex, command) ->
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
    tags = []

    zeroWidthMatch = captureIndices[0].start is captureIndices[0].end

    if @popRule
      # Pushing and popping a rule based on zero width matches at the same index
      # leads to an infinite loop. We bail on parsing if we detect that case here.
      if zeroWidthMatch and _.last(stack).zeroWidthMatch and _.last(stack).rule.anchorPosition is captureIndices[0].end
        return false

      {contentScopeName} = _.last(stack)
      tags.push(@grammar.endIdForScope(contentScopeName)) if contentScopeName
    else if @scopeName
      scopeName = @resolveScopeName(@scopeName, line, captureIndices)
      tags.push(@grammar.startIdForScope(scopeName))

    if @captures
      tags.push(@tagsForCaptureIndices(line, captureIndices.slice(), captureIndices, stack)...)
    else
      {start, end} = captureIndices[0]
      tags.push(end - start) unless end is start

    if @pushRule
      ruleToPush = @pushRule.getRuleToPush(line, captureIndices)
      ruleToPush.anchorPosition = captureIndices[0].end
      {contentScopeName} = ruleToPush
      if contentScopeName
        contentScopeName = @resolveScopeName(contentScopeName, line, captureIndices)
        tags.push(@grammar.startIdForScope(contentScopeName))
      stack.push({rule: ruleToPush, scopeName, contentScopeName, zeroWidthMatch})
    else
      {scopeName} = stack.pop() if @popRule
      tags.push(@grammar.endIdForScope(scopeName)) if scopeName

    tags

  tagsForCaptureRule: (rule, line, captureStart, captureEnd, stack) ->
    captureText = line.substring(captureStart, captureEnd)
    {tags} = rule.grammar.tokenizeLine(captureText, [stack..., {rule}], false, true, false)

    # only accept non empty tokens that don't exceed the capture end
    openScopes = []
    captureTags = []
    offset = 0
    for tag in tags when tag < 0 or (tag > 0 and offset < captureEnd)
      captureTags.push(tag)
      if tag >= 0
        offset += tag
      else
        if tag % 2 is 0
          openScopes.pop()
        else
          openScopes.push(tag)

    # close any scopes left open by matching this rule since we don't pass our stack
    while openScopes.length > 0
      captureTags.push(openScopes.pop() - 1)

    captureTags

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
  tagsForCaptureIndices: (line, currentCaptureIndices, allCaptureIndices, stack) ->
    parentCapture = currentCaptureIndices.shift()

    tags = []
    if scope = @captures[parentCapture.index]?.name
      parentCaptureScope = @resolveScopeName(scope, line, allCaptureIndices)
      tags.push(@grammar.startIdForScope(parentCaptureScope))

    if captureRule = @captures[parentCapture.index]?.rule
      captureTags = @tagsForCaptureRule(captureRule, line, parentCapture.start, parentCapture.end, stack)
      tags.push(captureTags...)
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
          tags.push(childCapture.start - previousChildCaptureEnd)

        captureTags = @tagsForCaptureIndices(line, currentCaptureIndices, allCaptureIndices, stack)
        tags.push(captureTags...)
        previousChildCaptureEnd = childCapture.end

      if parentCapture.end > previousChildCaptureEnd
        tags.push(parentCapture.end - previousChildCaptureEnd)

    if parentCaptureScope
      if tags.length > 1
        tags.push(@grammar.endIdForScope(parentCaptureScope))
      else
        tags.pop()

    tags

path = require 'path'

_ = require 'underscore-plus'
fs = require 'fs-plus'
{OnigRegExp} = require 'oniguruma'
{Emitter} = require 'emissary'

Injections = require './injections'
Pattern = require './pattern'
Rule = require './rule'
ScopeSelector = require './scope-selector'

pathSplitRegex = new RegExp("[#{_.escapeRegExp(path.sep)}.]")

module.exports =
class Grammar
  Emitter.includeInto(this)

  constructor: (@registry, options={}) ->
    {@name, @fileTypes, @scopeName, @foldingStopMarker} = options
    {injections, injectionSelector, patterns, repository, firstLineMatch} = options

    @repository = null
    @initialRule = null
    @maxTokensPerLine = 100

    @rawPatterns = patterns
    @rawRepository = repository
    @injections = new Injections(this, injections)

    if injectionSelector?
      @injectionSelector = new ScopeSelector(injectionSelector)
    else
      @injectionSelector = null

    if firstLineMatch
      @firstLineRegex = new OnigRegExp(firstLineMatch)
    else
      @firstLineRegex = null

    @fileTypes ?= []
    @includedGrammarScopes = []

  clearRules: ->
    @initialRule = null
    @repository = null

  getInitialRule: ->
    @initialRule ?= @createRule({@scopeName, patterns: @rawPatterns})

  getRepository: ->
    @repository ?= do =>
      repository = {}
      for name, data of @rawRepository
        data = {patterns: [data], tempName: name} if data.begin? or data.match?
        repository[name] = @createRule(data)
      repository

  addIncludedGrammarScope: (scope) ->
    @includedGrammarScopes.push(scope) unless _.include(@includedGrammarScopes, scope)

  grammarUpdated: (scopeName) ->
    return false unless _.include(@includedGrammarScopes, scopeName)
    @clearRules()
    @registry.grammarUpdated(@scopeName)
    @emit 'grammar-updated'
    true

  getScore: (filePath, contents) ->
    contents = fs.readFileSync(filePath, 'utf8') if not contents? and fs.isFileSync(filePath)

    if @registry.grammarOverrideForPath(filePath) is @scopeName
      2 + (filePath?.length ? 0)
    else if @matchesContents(contents)
      1 + (filePath?.length ? 0)
    else
      @getPathScore(filePath)

  matchesContents: (contents) ->
    return false unless contents? and @firstLineRegex?

    escaped = false
    numberOfNewlinesInRegex = 0
    for character in @firstLineRegex.source
      switch character
        when '\\'
          escaped = !escaped
        when 'n'
          numberOfNewlinesInRegex++ if escaped
          escaped = false
        else
          escaped = false
    lines = contents.split('\n')
    @firstLineRegex.test(lines[0..numberOfNewlinesInRegex].join('\n'))

  getPathScore: (filePath) ->
    return -1 unless filePath?

    pathComponents = filePath.split(pathSplitRegex)
    pathScore = -1
    for fileType in @fileTypes
      fileTypeComponents = fileType.split(pathSplitRegex)
      pathSuffix = pathComponents[-fileTypeComponents.length..-1]
      if _.isEqual(pathSuffix, fileTypeComponents)
        pathScore = Math.max(pathScore, fileType.length)

    pathScore

  createToken: (value, scopes) -> {value, scopes}

  createRule: (options) -> new Rule(this, @registry, options)

  createPattern: (options) -> new Pattern(this, @registry, options)

  tokenizeLine: (line, ruleStack, firstLine=false) ->
    if ruleStack?
      ruleStack = new Array(ruleStack...) # clone ruleStack
    else
      ruleStack = [@getInitialRule()]
    originalRuleStack = ruleStack

    tokens = []
    position = 0

    loop
      scopes = @scopesFromStack(ruleStack)
      previousRuleStackLength = ruleStack.length
      previousPosition = position

      if tokens.length >= @getMaxTokensPerLine() - 1
        token = @createToken(line[position..], scopes)
        tokens.push token
        ruleStack = originalRuleStack
        break

      break if position == line.length + 1 # include trailing newline position

      if match = _.last(ruleStack).getNextTokens(ruleStack, line, position, firstLine)
        { nextTokens, tokensStartPosition, tokensEndPosition } = match
        if position < tokensStartPosition # unmatched text before next tokens
          tokens.push(@createToken(line[position...tokensStartPosition], scopes))

        tokens.push(nextTokens...)
        position = tokensEndPosition
        break if position is line.length and nextTokens.length is 0 and ruleStack.length is previousRuleStackLength

      else # push filler token for unmatched text at end of line
        if position < line.length or line.length == 0
          tokens.push(@createToken(line[position...line.length], scopes))
        break

      if position == previousPosition
        if ruleStack.length == previousRuleStackLength
          console.error("Popping rule because it loops at column #{position} of line '#{line}'", _.clone(ruleStack))
          ruleStack.pop()
        else if ruleStack.length > previousRuleStackLength # Stack size increased with zero length match
          [penultimateRule, lastRule] = ruleStack[-2..]

          # Same exact rule was pushed but position wasn't advanced
          if lastRule? and lastRule == penultimateRule
            popStack = true

          # Rule with same scope name as previous rule was pushed but position wasn't advanced
          if lastRule?.scopeName? and penultimateRule.scopeName == lastRule.scopeName
            popStack = true

          if popStack
            ruleStack.pop()
            tokens.push(@createToken(line[position...line.length], scopes))
            break

    rule.clearAnchorPosition() for rule in ruleStack
    {tokens, ruleStack}

  tokenizeLines: (text) ->
    lines = text.split('\n')
    ruleStack = null
    for line, lineNumber in lines
      {tokens, ruleStack} = @tokenizeLine(line, ruleStack, lineNumber is 0)
      tokens

  getMaxTokensPerLine: ->
    @maxTokensPerLine

  scopesFromStack: (stack) ->
    scopes = []
    scopes.push(rule.scopeName) for rule in stack when rule.scopeName
    scopes

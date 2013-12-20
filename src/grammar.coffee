path = require 'path'

_ = require 'underscore-plus'
fs = require 'fs-plus'
{OnigRegExp, OnigScanner} = require 'oniguruma'
{Emitter} = require 'emissary'

Injections = require './injections'
Rule = require './rule'
ScopeSelector = require './scope-selector'

pathSplitRegex = new RegExp("[#{_.escapeRegExp(path.sep)}.]")

### Internal ###

module.exports =
class Grammar
  Emitter.includeInto(this)

  @load: (grammarPath, done) ->
    fs.readObject grammarPath, (error, object) ->
      if error?
        done(error)
      else
        done(null, new Grammar(object))

  @loadSync: (grammarPath) ->
    new Grammar(fs.readObjectSync(grammarPath))

  name: null
  rawPatterns: null
  rawRepository: null
  fileTypes: null
  scopeName: null
  repository: null
  initialRule: null
  firstLineRegex: null
  includedGrammarScopes: null
  maxTokensPerLine: 100

  constructor: ({@name, @fileTypes, @scopeName, injections, injectionSelector, patterns, repository, @foldingStopMarker, firstLineMatch}) ->
    @rawPatterns = patterns
    @rawRepository = repository
    @injections = new Injections(this, injections)

    if injectionSelector?
      @injectionSelector = new ScopeSelector(injectionSelector)

    @firstLineRegex = new OnigRegExp(firstLineMatch) if firstLineMatch
    @fileTypes ?= []
    @includedGrammarScopes = []

  clearRules: ->
    @initialRule = null
    @repository = null

  getInitialRule: ->
    @initialRule ?= new Rule({grammar: this, @scopeName, patterns: @rawPatterns})

  getRepository: ->
    @repository ?= do =>
      repository = {}
      for name, data of @rawRepository
        data = {patterns: [data], tempName: name} if data.begin? or data.match?
        repository[name] = new Rule(this, data)
      repository

  addIncludedGrammarScope: (scope) ->
    @includedGrammarScopes.push(scope) unless _.include(@includedGrammarScopes, scope)

  grammarUpdated: (scopeName) ->
    return false unless _.include(@includedGrammarScopes, scopeName)
    @clearRules()
    atom.syntax.grammarUpdated(@scopeName)
    @emit 'grammar-updated'
    true

  getScore: (filePath, contents) ->
    contents = fs.readFileSync(filePath, 'utf8') if not contents? and fs.isFileSync(filePath)

    if atom.syntax.grammarOverrideForPath(filePath) is @scopeName
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
    @fileTypes.forEach (fileType) ->
      fileTypeComponents = fileType.split(pathSplitRegex)
      pathSuffix = pathComponents[-fileTypeComponents.length..-1]
      if _.isEqual(pathSuffix, fileTypeComponents)
        pathScore = Math.max(pathScore, fileType.length)

    pathScore

  createToken: (value, scopes) -> {value, scopes}

  tokenizeLine: (line, ruleStack=[@getInitialRule()], firstLine=false) ->
    originalRuleStack = ruleStack
    ruleStack = new Array(ruleStack...) # clone ruleStack
    tokens = []
    position = 0

    loop
      scopes = @scopesFromStack(ruleStack)
      previousRuleStackLength = ruleStack.length
      previousPosition = position

      if tokens.length >= (@getMaxTokensPerLine() - 1)
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

    ruleStack.forEach (rule) -> rule.clearAnchorPosition()
    { tokens, ruleStack }

  tokenizeLines: (text) ->
    lines = text.split('\n')
    ruleStack = null
    for line, i in lines
      { tokens, ruleStack } = @tokenizeLine(line, ruleStack, i is 0)
      tokens

  getMaxTokensPerLine: ->
    @maxTokensPerLine

  scopesFromStack: (stack) ->
    _.compact(_.pluck(stack, "scopeName"))
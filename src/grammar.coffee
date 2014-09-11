path = require 'path'

_ = require 'underscore-plus'
fs = require 'fs-plus'
{OnigRegExp} = require 'oniguruma'
EmitterMixin = require('emissary').Emitter
{Emitter} = require 'event-kit'
Grim = require 'grim'

Injections = require './injections'
Pattern = require './pattern'
Rule = require './rule'
ScopeSelector = require './scope-selector'

pathSplitRegex = new RegExp("[/.]")

# Extended: Grammar that tokenizes lines of text.
#
# This class should not be instantiated directly but instead obtained from
# a {GrammarRegistry} by calling {GrammarRegistry::loadGrammar}.
module.exports =
class Grammar
  EmitterMixin.includeInto(this)

  constructor: (@registry, options={}) ->
    {@name, @fileTypes, @scopeName, @foldingStopMarker, @maxTokensPerLine} = options
    {injections, injectionSelector, patterns, repository, firstLineMatch} = options

    @emitter = new Emitter
    @repository = null
    @initialRule = null

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

  ###
  Section: Event Subscription
  ###

  # Public: Invoke the given callback when this grammar is updated due to a
  # grammar it depends on being added or removed from the registry.
  #
  # * `callback` {Function} to call when this grammar is updated.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidUpdate: (callback) ->
    @emitter.on 'did-update', callback

  on: (eventName) ->
    if eventName is 'did-update'
      Grim.deprecate("Call Grammar::onDidUpdate instead")
    else
      Grim.deprecate("Call explicit event subscription methods instead")

    EmitterMixin::on.apply(this, arguments)

  ###
  Section: Tokenizing
  ###

  # Public: Tokenize all lines in the given text.
  #
  # * `text` A {String} containing one or more lines.
  #
  # Returns an {Array} of token arrays for each line tokenized.
  tokenizeLines: (text) ->
    lines = text.split('\n')
    ruleStack = null
    for line, lineNumber in lines
      {tokens, ruleStack} = @tokenizeLine(line, ruleStack, lineNumber is 0)
      tokens

  # Public: Tokenize the line of text.
  #
  # * `line` A {String} of text to tokenize.
  # * `ruleStack` An optional {Array} of rules previously returned from this
  #   method. This should be null when tokenizing the first line in the file.
  # * `firstLine` A optional {Boolean} denoting whether this is the first line
  #   in the file which defaults to `false`. This should be `true`
  #   when tokenizing the first line in the file.
  #
  # Returns an {Object} containing the following properties:
  # * `token` An {Array} of tokens covering the entire line of text.
  # * `ruleStack` An {Array} of rules representing the tokenized state at the
  #   end of the line. These should be passed back into this method when
  #   tokenizing the next line in the file.
  tokenizeLine: (line, ruleStack, firstLine=false) ->
    if ruleStack?
      ruleStack = ruleStack.slice()
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
        {nextTokens, tokensStartPosition, tokensEndPosition} = match

        # Unmatched text before next tokens
        if position < tokensStartPosition
          tokens.push(@createToken(line[position...tokensStartPosition], scopes))

        tokens.push(nextTokens...)
        position = tokensEndPosition


      else
        # Push filler token for unmatched text at end of line
        if position < line.length or line.length == 0
          tokens.push(@createToken(line[position...line.length], scopes))
        break

      if position == previousPosition
        if ruleStack.length == previousRuleStackLength
          console.error("Popping rule because it loops at column #{position} of line '#{line}'", _.clone(ruleStack))
          if ruleStack.length > 1
            ruleStack.pop()
          else
            if position < line.length or (line.length == 0 and tokens.length is 0)
              tokens.push(@createToken(line[position...line.length], scopes))
            break
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

  activate: ->
    @registry.addGrammar(this)

  deactivate: ->
    @emitter = new Emitter
    @registry.removeGrammar(this)

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
    @emitter.emit 'did-update'
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
    @firstLineRegex.testSync(lines[0..numberOfNewlinesInRegex].join('\n'))

  getPathScore: (filePath) ->
    return -1 unless filePath

    filePath = filePath.replace(/\\/g, '/') if process.platform is 'win32'

    pathComponents = filePath.toLowerCase().split(pathSplitRegex)
    pathScore = -1
    for fileType in @fileTypes
      fileTypeComponents = fileType.toLowerCase().split(pathSplitRegex)
      pathSuffix = pathComponents[-fileTypeComponents.length..-1]
      if _.isEqual(pathSuffix, fileTypeComponents)
        pathScore = Math.max(pathScore, fileType.length)

    pathScore

  createToken: (value, scopes) -> @registry.createToken(value, scopes)

  createRule: (options) -> new Rule(this, @registry, options)

  createPattern: (options) -> new Pattern(this, @registry, options)

  getMaxTokensPerLine: ->
    @maxTokensPerLine

  scopesFromStack: (stack, rule, endPatternMatch) ->
    scopes = []
    for {scopeName, contentScopeName} in stack
      scopes.push(scopeName) if scopeName
      scopes.push(contentScopeName) if contentScopeName

    # Pop the last content name scope if the end pattern at the top of the stack
    # was matched since only text between the begin/end patterns should have the
    # content name scope
    if endPatternMatch and rule?.contentScopeName and rule is stack[stack.length - 1]
      scopes.pop()

    scopes

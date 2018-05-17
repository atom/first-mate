_ = require 'underscore-plus'
CSON = require 'season'
{Emitter, Disposable} = require 'event-kit'
Grim = require 'grim'

Grammar = require './grammar'
NullGrammar = require './null-grammar'

# Extended: Registry containing one or more grammars.
module.exports =
class GrammarRegistry
  constructor: (options={}) ->
    @maxTokensPerLine = options.maxTokensPerLine ? Infinity
    @maxLineLength = options.maxLineLength ? Infinity
    @nullGrammar = new NullGrammar(this)
    @clear()

  clear: ->
    @emitter = new Emitter
    @grammars = []
    @grammarsByScopeName = {}
    @injectionGrammars = []
    @grammarOverridesByPath = {}
    @scopeIdCounter = -1
    @idsByScope = {}
    @scopesById = {}
    @addGrammar(@nullGrammar)

  ###
  Section: Event Subscription
  ###

  # Public: Invoke the given callback when a grammar is added to the registry.
  #
  # * `callback` {Function} to call when a grammar is added.
  #   * `grammar` {Grammar} that was added.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidAddGrammar: (callback) ->
    @emitter.on 'did-add-grammar', callback

  # Public: Invoke the given callback when a grammar is updated due to a grammar
  # it depends on being added or removed from the registry.
  #
  # * `callback` {Function} to call when a grammar is updated.
  #   * `grammar` {Grammar} that was updated.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidUpdateGrammar: (callback) ->
    @emitter.on 'did-update-grammar', callback

  # Public: Invoke the given callback when a grammar is removed from the registry.
  #
  # * `callback` {Function} to call when a grammar is removed.
  #   * `grammar` {Grammar} that was removed.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidRemoveGrammar: (callback) ->
    @emitter.on 'did-remove-grammar', callback

  ###
  Section: Managing Grammars
  ###

  # Public: Get all the grammars in this registry.
  #
  # Returns a non-empty {Array} of {Grammar} instances.
  getGrammars: ->
    _.clone(@grammars)

  # Public: Get a grammar with the given scope name.
  #
  # * `scopeName` A {String} such as `"source.js"`.
  #
  # Returns a {Grammar} or undefined.
  grammarForScopeName: (scopeName) ->
    @grammarsByScopeName[scopeName]

  # Public: Add a grammar to this registry.
  #
  # A 'grammar-added' event is emitted after the grammar is added.
  #
  # * `grammar` The {Grammar} to add. This should be a value previously returned
  #   from {::readGrammar} or {::readGrammarSync}.
  #
  # Returns a {Disposable} on which `.dispose()` can be called to remove the
  # grammar.
  addGrammar: (grammar) ->
    @grammars.push(grammar)
    @grammarsByScopeName[grammar.scopeName] = grammar
    @injectionGrammars.push(grammar) if grammar.injectionSelector?
    @grammarUpdated(grammar.scopeName)
    @emit 'grammar-added', grammar if Grammar.includeDeprecatedAPIs
    @emitter.emit 'did-add-grammar', grammar
    new Disposable => @removeGrammar(grammar)

  removeGrammar: (grammar) ->
    _.remove(@grammars, grammar)
    delete @grammarsByScopeName[grammar.scopeName]
    _.remove(@injectionGrammars, grammar)
    @grammarUpdated(grammar.scopeName)
    @emitter.emit 'did-remove-grammar', grammar
    undefined

  # Public: Remove the grammar with the given scope name.
  #
  # * `scopeName` A {String} such as `"source.js"`.
  #
  # Returns the removed {Grammar} or undefined.
  removeGrammarForScopeName: (scopeName) ->
    grammar = @grammarForScopeName(scopeName)
    @removeGrammar(grammar) if grammar?
    grammar

  # Public: Read a grammar synchronously but don't add it to the registry.
  #
  # * `grammarPath` A {String} absolute file path to a grammar file.
  #
  # Returns a {Grammar}.
  readGrammarSync: (grammarPath) ->
    grammar = CSON.readFileSync(grammarPath) ? {}
    if typeof grammar.scopeName is 'string' and grammar.scopeName.length > 0
      @createGrammar(grammarPath, grammar)
    else
      throw new Error("Grammar missing required scopeName property: #{grammarPath}")

  # Public: Read a grammar asynchronously but don't add it to the registry.
  #
  # * `grammarPath` A {String} absolute file path to a grammar file.
  # * `callback` A {Function} to call when read with the following arguments:
  #   * `error` An {Error}, may be null.
  #   * `grammar` A {Grammar} or null if an error occured.
  #
  # Returns undefined.
  readGrammar: (grammarPath, callback) ->
    CSON.readFile grammarPath, (error, grammar={}) =>
      if error?
        callback?(error)
      else
        if typeof grammar.scopeName is 'string' and grammar.scopeName.length > 0
          callback?(null, @createGrammar(grammarPath, grammar))
        else
          callback?(new Error("Grammar missing required scopeName property: #{grammarPath}"))

    undefined

  # Public: Read a grammar synchronously and add it to this registry.
  #
  # * `grammarPath` A {String} absolute file path to a grammar file.
  #
  # Returns a {Grammar}.
  loadGrammarSync: (grammarPath) ->
    grammar = @readGrammarSync(grammarPath)
    @addGrammar(grammar)
    grammar

  # Public: Read a grammar asynchronously and add it to the registry.
  #
  # * `grammarPath` A {String} absolute file path to a grammar file.
  # * `callback` A {Function} to call when loaded with the following arguments:
  #   * `error` An {Error}, may be null.
  #   * `grammar` A {Grammar} or null if an error occured.
  #
  # Returns undefined.
  loadGrammar: (grammarPath, callback) ->
    @readGrammar grammarPath, (error, grammar) =>
      if error?
        callback?(error)
      else
        @addGrammar(grammar)
        callback?(null, grammar)

    undefined

  startIdForScope: (scope) ->
    unless id = @idsByScope[scope]
      id = @scopeIdCounter
      @scopeIdCounter -= 2
      @idsByScope[scope] = id
      @scopesById[id] = scope
    id

  endIdForScope: (scope) ->
    @startIdForScope(scope) - 1

  scopeForId: (id) ->
    if (id % 2) is -1
      @scopesById[id] # start id
    else
      @scopesById[id + 1] # end id

  grammarUpdated: (scopeName) ->
    for grammar in @grammars when grammar.scopeName isnt scopeName
      if grammar.grammarUpdated(scopeName)
        @emit 'grammar-updated', grammar if Grammar.includeDeprecatedAPIs
        @emitter.emit 'did-update-grammar', grammar
    return

  createGrammar: (grammarPath, object) ->
    object.maxTokensPerLine ?= @maxTokensPerLine
    object.maxLineLength ?= @maxLineLength
    if object.limitLineLength is false
      object.maxLineLength = Infinity
    grammar = new Grammar(this, object)
    grammar.path = grammarPath
    grammar

  decodeTokens: (lineText, tags, scopeTags = [], fn) ->
    offset = 0
    scopeNames = scopeTags.map (tag) => @scopeForId(tag)

    tokens = []
    for tag, index in tags
      # positive numbers indicate string content with length equaling the number
      if tag >= 0
        token = {
          value: lineText.substring(offset, offset + tag)
          scopes: scopeNames.slice()
        }
        token = fn(token, index) if fn?
        tokens.push(token)
        offset += tag

      # odd negative numbers are begin scope tags
      else if (tag % 2) is -1
        scopeTags.push(tag)
        scopeNames.push(@scopeForId(tag))

      # even negative numbers are end scope tags
      else
        scopeTags.pop()
        expectedScopeName = @scopeForId(tag + 1)
        poppedScopeName = scopeNames.pop()
        unless poppedScopeName is expectedScopeName
          throw new Error("Expected popped scope to be #{expectedScopeName}, but it was #{poppedScopeName}")

    tokens

if Grim.includeDeprecatedAPIs
  EmitterMixin = require('emissary').Emitter
  EmitterMixin.includeInto(GrammarRegistry)

  GrammarRegistry::on = (eventName) ->
    switch eventName
      when 'grammar-added'
        Grim.deprecate("Call GrammarRegistry::onDidAddGrammar instead")
      when 'grammar-updated'
        Grim.deprecate("Call GrammarRegistry::onDidUpdateGrammar instead")
      else
        Grim.deprecate("Call explicit event subscription methods instead")

    EmitterMixin::on.apply(this, arguments)

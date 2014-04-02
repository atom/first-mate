_ = require 'underscore-plus'
CSON = require 'season'
{Emitter} = require 'emissary'

Grammar = require './grammar'
NullGrammar = require './null-grammar'

# Public: Registry containing one or more grammars.
module.exports =
class GrammarRegistry
  Emitter.includeInto(this)

  constructor: (options={}) ->
    @maxTokensPerLine = options.maxTokensPerLine ? Infinity
    @grammars = []
    @grammarsByScopeName = {}
    @injectionGrammars = []
    @grammarOverridesByPath = {}
    @nullGrammar = new NullGrammar(this)
    @addGrammar(@nullGrammar)

  # Public: Get all the grammars in this registry.
  #
  # Returns a non-empty {Array} of {Grammar} instances.
  getGrammars: ->
    _.clone(@grammars)

  # Public: Get a grammar with the given scope name.
  #
  # scopeName - A {String} such as `"source.js"`.
  #
  # Returns a {Grammar} or undefined.
  grammarForScopeName: (scopeName) ->
    @grammarsByScopeName[scopeName]

  # Public: Remove a grammar from this registry.
  #
  # grammar - The {Grammar} to remove.
  removeGrammar: (grammar) ->
    _.remove(@grammars, grammar)
    delete @grammarsByScopeName[grammar.scopeName]
    _.remove(@injectionGrammars, grammar)
    @grammarUpdated(grammar.scopeName)

  # Public: Remove the grammar with the given scope name.
  #
  # scopeName - A {String} such as `"source.js"`.
  removeGrammarForScopeName: (scopeName) ->
    grammar = @grammarForScopeName(scopeName)
    @removeGrammar(grammar) if grammar?

  # Public: Add a grammar to this registry.
  #
  # A 'grammar-added' event is emitted after the grammar is added.
  #
  # grammar - The {Grammar} to add. This should be a value previously returned
  #           from {::readGrammar} or {::readGrammarSync}.
  addGrammar: (grammar) ->
    @grammars.push(grammar)
    @grammarsByScopeName[grammar.scopeName] = grammar
    @injectionGrammars.push(grammar) if grammar.injectionSelector?
    @grammarUpdated(grammar.scopeName)
    @emit 'grammar-added', grammar

  # Public: Read a grammar synchronously but don't add it to the registry.
  #
  # grammarPath - A {String} absolute file path to a grammar file.
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
  # grammarPath - A {String} absolute file path to a grammar file.
  # callback    - A {Function} to call when loaded with `(error, grammar)`
  #               arguments.
  readGrammar: (grammarPath, callback) ->
    CSON.readFile grammarPath, (error, grammar={}) =>
      if error?
        callback?(error)
      else
        if typeof grammar.scopeName is 'string' and grammar.scopeName.length > 0
          callback?(null, @createGrammar(grammarPath, grammar))
        else
          callback?(new Error("Grammar missing required scopeName property: #{grammarPath}"))

  # Public: Read a grammar synchronously and add it to this registry.
  #
  # grammarPath - A {String} absolute file path to a grammar file.
  #
  # Returns a {Grammar}.
  loadGrammarSync: (grammarPath) ->
    grammar = @readGrammarSync(grammarPath)
    @addGrammar(grammar)
    grammar

  # Public: Read a grammar asynchronously and add it to the registry.
  #
  # grammarPath - A {String} absolute file path to a grammar file.
  # callback    - A {Function} to call when loaded with `(error, grammar)`
  #               arguments.
  loadGrammar: (grammarPath, callback) ->
    @readGrammar grammarPath, (error, grammar) =>
      if error?
        callback?(error)
      else
        @addGrammar(grammar)
        callback?(null, grammar)

  # Public: Get the grammar override for the given file path.
  #
  # filePath - A {String} file path.
  #
  # Returns a {Grammar} or undefined.
  grammarOverrideForPath: (filePath) ->
    @grammarOverridesByPath[filePath]

  # Public: Set the grammar override for the given file path.
  #
  # filePath  - A non-empty {String} file path.
  # scopeName - A {String} such as `"source.js"`.
  #
  # Returns a {Grammar} or undefined.
  setGrammarOverrideForPath: (filePath, scopeName) ->
    if filePath
      @grammarOverridesByPath[filePath] = scopeName

  # Public: Remove the grammar override for the given file path.
  #
  # filePath - A {String} file path.
  clearGrammarOverrideForPath: (filePath) ->
    delete @grammarOverridesByPath[filePath]

  # Public: Remove all grammar overrides.
  clearGrammarOverrides: ->
    @grammarOverridesByPath = {}

  # Public: Select a grammar for the given file path and file contents.
  #
  # This picks the best match by checking the file path and contents against
  # each grammar.
  #
  # filePath     - A {String} file path.
  # fileContents - A {String} of text for the file path.
  #
  # Returns a {Grammar}, never null.
  selectGrammar: (filePath, fileContents) ->
    _.max @grammars, (grammar) -> grammar.getScore(filePath, fileContents)

  createToken: (value, scopes) -> {value, scopes}

  grammarUpdated: (scopeName) ->
    for grammar in @grammars when grammar.scopeName isnt scopeName
      @emit 'grammar-updated', grammar if grammar.grammarUpdated(scopeName)

  createGrammar: (grammarPath, object) ->
    object.maxTokensPerLine ?= @maxTokensPerLine
    grammar = new Grammar(this, object)
    grammar.path = grammarPath
    grammar

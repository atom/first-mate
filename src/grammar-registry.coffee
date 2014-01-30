_ = require 'underscore-plus'
{Emitter} = require 'emissary'
fs = require 'fs-plus'

Grammar = require './grammar'
NullGrammar = require './null-grammar'

module.exports =
class GrammarRegistry
  Emitter.includeInto(this)

  constructor: ->
    @grammars = []
    @grammarsByScopeName = {}
    @injectionGrammars = []
    @grammarOverridesByPath = {}
    @nullGrammar = new NullGrammar(this)
    @addGrammar(@nullGrammar)

  createToken: (value, scopes) -> {value, scopes}

  addGrammar: (grammar) ->
    @grammars.push(grammar)
    @grammarsByScopeName[grammar.scopeName] = grammar
    @injectionGrammars.push(grammar) if grammar.injectionSelector?
    @grammarUpdated(grammar.scopeName)
    @emit 'grammar-added', grammar

  removeGrammar: (grammar) ->
    _.remove(@grammars, grammar)
    delete @grammarsByScopeName[grammar.scopeName]
    _.remove(@injectionGrammars, grammar)
    @grammarUpdated(grammar.scopeName)

  removeGrammarForScopeName: (scopeName) ->
    grammar = @grammarForScopeName(scopeName)
    @removeGrammar(grammar) if grammar?

  grammarUpdated: (scopeName) ->
    for grammar in @grammars when grammar.scopeName isnt scopeName
      @emit 'grammar-updated', grammar if grammar.grammarUpdated(scopeName)

  grammarForScopeName: (scopeName) ->
    @grammarsByScopeName[scopeName]

  createGrammar: (grammarPath, object) ->
    grammar = new Grammar(this, object)
    grammar.path = grammarPath
    grammar

  readGrammarSync: (grammarPath) ->
    @createGrammar(grammarPath, fs.readObjectSync(grammarPath))

  readGrammar: (grammarPath, callback) ->
    fs.readObject grammarPath, (error, object) =>
      if error?
        callback?(error)
      else
        callback?(null, @createGrammar(grammarPath, object))

  loadGrammarSync: (grammarPath) ->
    grammar = @readGrammarSync(grammarPath)
    @addGrammar(grammar)
    grammar

  loadGrammar: (grammarPath, callback) ->
    fs.readObject grammarPath, (error, object) =>
      if error?
        callback?(error)
      else
        grammar = @createGrammar(grammarPath, object)
        @addGrammar(grammar)
        callback?(null, grammar)

  grammarOverrideForPath: (path) ->
    @grammarOverridesByPath[path]

  setGrammarOverrideForPath: (path, scopeName) ->
    @grammarOverridesByPath[path] = scopeName

  clearGrammarOverrideForPath: (path) ->
    delete @grammarOverridesByPath[path]

  clearGrammarOverrides: ->
    @grammarOverridesByPath = {}

  selectGrammar: (filePath, fileContents) ->
    _.max @grammars, (grammar) -> grammar.getScore(filePath, fileContents)

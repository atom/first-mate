_ = require 'underscore-plus'
{Emitter} = require 'emissary'
fs = require 'fs-plus'

Grammar = require './grammar'
NullGrammar = require './null-grammar'

module.exports =
class Registry
  Emitter.includeInto(this)

  constructor: ->
    @grammars = []
    @grammarsByScopeName = {}
    @injectionGrammars = []
    @grammarOverridesByPath = {}
    @nullGrammar = new NullGrammar()
    @addGrammar(@nullGrammar)

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

  loadGrammarSync: (grammarPath) ->
    grammar = new Grammar(this, fs.readObjectSync(grammarPath))
    @addGrammar(grammar)
    grammar

  loadGrammar: (grammarPath, done) ->
    fs.readObject grammarPath, (error, object) =>
      if error?
        done?(error)
      else
        grammar = new Grammar(this, object)
        @addGrammar(grammar)
        done?(null, grammar)

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

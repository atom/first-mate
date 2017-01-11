path = require 'path'
GrammarRegistry = require '../lib/grammar-registry'

describe "GrammarRegistry", ->
  registry = null

  loadGrammarSync = (name) ->
    registry.loadGrammarSync(path.join(__dirname, 'fixtures', name))

  describe "when the grammar has no scope name", ->
    it "throws an error", ->
      grammarPath = path.join(__dirname, 'fixtures', 'no-scope-name.json')
      registry = new GrammarRegistry()
      expect(-> registry.loadGrammarSync(grammarPath)).toThrow()

      callback = jasmine.createSpy('callback')
      registry.loadGrammar(grammarPath, callback)

      waitsFor ->
        callback.callCount is 1

      runs ->
        expect(callback.argsForCall[0][0].message.length).toBeGreaterThan 0

  describe "maxTokensPerLine option", ->
    it "set the value on each created grammar and limits the number of tokens per line to that value", ->
      registry = new GrammarRegistry(maxTokensPerLine: 2)
      loadGrammarSync('json.json')

      grammar = registry.grammarForScopeName('source.json')
      expect(grammar.maxTokensPerLine).toBe 2

      {line, tags} = grammar.tokenizeLine("{ }")
      tokens = registry.decodeTokens(line, tags)
      expect(tokens.length).toBe 2

  describe "maxLineLength option", ->
    it "should set the value on each created grammar and doesn't tokenize more than that many characters of the line", ->
      registry = new GrammarRegistry(maxLineLength: 1)
      loadGrammarSync('json.json')

      grammar = registry.grammarForScopeName('source.json')
      expect(grammar.maxLineLength).toBe 1

      {line, tags} = grammar.tokenizeLine("{ \"test\":\"object\" }")
      tokens = registry.decodeTokens(line, tags)
      expect(tokens.length).toBe 2

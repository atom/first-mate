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
    it "limits the number of tokens created by the parser per line", ->
      registry = new GrammarRegistry(maxTokensPerLine: 2)
      loadGrammarSync('json.json')

      grammar = registry.grammarForScopeName('source.json')
      {line, tags} = grammar.tokenizeLine("{ }")
      tokens = registry.decodeTokens(line, tags)
      expect(tokens.length).toBe 2

  describe "maxLineLength option", ->
    it "limits the number of characters scanned by the parser per line", ->
      registry = new GrammarRegistry(maxLineLength: 10)
      loadGrammarSync('json.json')
      grammar = registry.grammarForScopeName('source.json')

      {ruleStack: initialRuleStack} = grammar.tokenizeLine('[')
      {line, tags, ruleStack} = grammar.tokenizeLine('{"foo": "this is a long value"}', initialRuleStack)
      tokens = registry.decodeTokens(line, tags)

      expect(ruleStack.map((entry) -> entry.scopeName)).toEqual(initialRuleStack.map((entry) -> entry.scopeName))
      expect(tokens.map((token) -> token.value)).toEqual([
        '{',
        '"',
        'foo',
        '"',
        ':',
        ' ',
        '"',
        'this is a long value"}'
      ])

    it "does not apply if the grammar's limitLineLength option is set to false", ->
      registry = new GrammarRegistry(maxLineLength: 10)
      loadGrammarSync('no-line-length-limit.cson')
      grammar = registry.grammarForScopeName('source.long-lines')

      {tokens} = grammar.tokenizeLine("hello goodbye hello goodbye hello")
      expect(tokens.length).toBe(5)

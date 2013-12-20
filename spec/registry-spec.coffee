path = require 'path'
Registry = require '../src/registry'

describe "Registry", ->
  describe "::loadGrammarSync", ->
    it "returns a grammar for the file path specified", ->
      registry = new Registry()
      grammar = registry.loadGrammarSync(path.join(__dirname, 'fixtures', 'hello.cson'))
      expect(grammar).not.toBeNull()

      {tokens} = grammar.tokenizeLine('hello world!')
      expect(tokens.length).toBe 4

      expect(tokens[0].value).toBe 'hello'
      expect(tokens[0].scopes).toEqual ['source.hello', 'prefix.hello']

      expect(tokens[1].value).toBe ' '
      expect(tokens[1].scopes).toEqual ['source.hello']

      expect(tokens[2].value).toBe 'world'
      expect(tokens[2].scopes).toEqual ['source.hello', 'suffix.hello']

      expect(tokens[3].value).toBe '!'
      expect(tokens[3].scopes).toEqual ['source.hello', 'suffix.hello', 'emphasis.hello']

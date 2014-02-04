GrammarRegistry = require '../lib/grammar-registry'

describe "GrammarRegistry", ->
  describe "grammar overrides", ->
    it "stores the override scope name for a path", ->
      registry = new GrammarRegistry()

      expect(registry.grammarOverrideForPath('foo.js.txt')).toBeUndefined()
      expect(registry.grammarOverrideForPath('bar.js.txt')).toBeUndefined()

      registry.setGrammarOverrideForPath('foo.js.txt', 'source.js')
      expect(registry.grammarOverrideForPath('foo.js.txt')).toBe 'source.js'

      registry.setGrammarOverrideForPath('bar.js.txt', 'source.coffee')
      expect(registry.grammarOverrideForPath('bar.js.txt')).toBe 'source.coffee'

      registry.clearGrammarOverrideForPath('foo.js.txt')
      expect(registry.grammarOverrideForPath('foo.js.txt')).toBeUndefined()
      expect(registry.grammarOverrideForPath('bar.js.txt')).toBe 'source.coffee'

      registry.clearGrammarOverrides()
      expect(registry.grammarOverrideForPath('bar.js.txt')).toBeUndefined()

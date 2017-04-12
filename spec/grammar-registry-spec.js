/* eslint-env mocha */

import {assert} from 'chai'
import sinon from 'sinon'

import path from 'path'
import GrammarRegistry from '../lib/grammar-registry'

const sandbox = sinon.sandbox.create()

describe('GrammarRegistry', () => {
  afterEach(() => {
    sandbox.restore()
  })

  let registry = null

  const loadGrammarSync = name => registry.loadGrammarSync(path.join(__dirname, 'fixtures', name))

  describe('when the grammar has no scope name', () => {
    it('throws an error', (done) => {
      const grammarPath = path.join(__dirname, 'fixtures', 'no-scope-name.json')
      registry = new GrammarRegistry()
      assert.throws(() => registry.loadGrammarSync(grammarPath))

      registry.loadGrammar(grammarPath, (error, grammar) => {
        assert.isNotNull(error)
        assert.isAbove(error.message.length, 0)
        done()
      })
    })
  })

  describe('maxTokensPerLine option', () => {
    it('limits the number of tokens created by the parser per line', () => {
      registry = new GrammarRegistry({maxTokensPerLine: 2})
      loadGrammarSync('json.json')

      const grammar = registry.grammarForScopeName('source.json')
      const {line, tags} = grammar.tokenizeLine('{ }')
      const tokens = registry.decodeTokens(line, tags)
      assert.equal(tokens.length, 2)
    })
  })

  describe('maxLineLength option', () => {
    it('limits the number of characters scanned by the parser per line', () => {
      registry = new GrammarRegistry({maxLineLength: 10})
      loadGrammarSync('json.json')
      const grammar = registry.grammarForScopeName('source.json')

      const {ruleStack: initialRuleStack} = grammar.tokenizeLine('[')
      const {line, tags, ruleStack} = grammar.tokenizeLine('{"foo": "this is a long value"}', initialRuleStack)
      const tokens = registry.decodeTokens(line, tags)

      assert.deepEqual(ruleStack.map(entry => entry.scopeName), initialRuleStack.map(entry => entry.scopeName))
      assert.deepEqual(tokens.map(token => token.value), [
        '{',
        '"',
        'foo',
        '"',
        ':',
        ' ',
        '"',
        'this is a long value"}'
      ])
    })

    it("does not apply if the grammar's limitLineLength option is set to false", () => {
      registry = new GrammarRegistry({maxLineLength: 10})
      loadGrammarSync('no-line-length-limit.cson')
      const grammar = registry.grammarForScopeName('source.long-lines')

      const {tokens} = grammar.tokenizeLine('hello goodbye hello goodbye hello')
      assert.equal(tokens.length, 5)
    })
  })
})

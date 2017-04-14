/* eslint-env mocha */

import {assert} from 'chai'
import sinon from 'sinon'

import path from 'path'
import fs from 'fs-plus'
import GrammarRegistry from '../lib/grammar-registry'
import Grammar from '../lib/grammar'

const sandbox = sinon.sandbox.create()

describe('Grammar tokenization', () => {
  let [grammar, registry] = []

  const loadGrammarSync = name => registry.loadGrammarSync(path.join(__dirname, 'fixtures', name))

  beforeEach(() => {
    registry = new GrammarRegistry()
    loadGrammarSync('text.json')
    loadGrammarSync('javascript.json')
    loadGrammarSync('javascript-regex.json')
    loadGrammarSync('coffee-script.json')
    loadGrammarSync('ruby.json')
    loadGrammarSync('html-erb.json')
    loadGrammarSync('html.json')
    loadGrammarSync('php.json')
    loadGrammarSync('python.cson')
    loadGrammarSync('python-regex.cson')
  })

  afterEach(() => {
    sandbox.restore()
  })

  describe('when the registry is empty', () => {
    it('allows injections into the null grammar', () => {
      registry = new GrammarRegistry()
      loadGrammarSync('hyperlink.json')

      grammar = registry.nullGrammar
      const {line, tags} = grammar.tokenizeLine('http://github.com')
      const tokens = registry.decodeTokens(line, tags)
      assert.equal(tokens.length, 1)
      assert.equal(tokens[0].value, 'http://github.com')
      assert.deepEqual(tokens[0].scopes, ['text.plain.null-grammar', 'markup.underline.link.http.hyperlink'])
    })
  })

  describe('Registry::loadGrammarSync', () => {
    it('returns a grammar for the file path specified', () => {
      grammar = loadGrammarSync('hello.cson')
      assert.equal(fs.isFileSync(grammar.path), true)
      assert.notEqual(grammar, null)

      const {line, tags} = grammar.tokenizeLine('hello world!')
      const tokens = registry.decodeTokens(line, tags)
      assert.equal(tokens.length, 4)

      assert.equal(tokens[0].value, 'hello')
      assert.deepEqual(tokens[0].scopes, ['source.hello', 'prefix.hello'])

      assert.equal(tokens[1].value, ' ')
      assert.deepEqual(tokens[1].scopes, ['source.hello'])

      assert.equal(tokens[2].value, 'world')
      assert.deepEqual(tokens[2].scopes, ['source.hello', 'suffix.hello'])

      assert.equal(tokens[3].value, '!')
      assert.deepEqual(tokens[3].scopes, ['source.hello', 'suffix.hello', 'emphasis.hello'])
    })
  })

  describe('::tokenizeLine(line, ruleStack)', () => {
    describe('when the entire line matches a single pattern with no capture groups', () => {
      it('returns a single token with the correct scope', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('return')

        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: 'return', scopes: ['source.coffee', 'keyword.control.coffee']}
        ])
      })
    })

    describe('when the entire line matches a single pattern with capture groups', () => {
      it('returns a single token with the correct scope', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('new foo.bar.Baz')
        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: 'new', scopes: ['source.coffee', 'meta.class.instance.constructor', 'keyword.operator.new.coffee']},
          {value: ' ', scopes: ['source.coffee', 'meta.class.instance.constructor']},
          {value: 'foo.bar.Baz', scopes: ['source.coffee', 'meta.class.instance.constructor', 'entity.name.type.instance.coffee']}
        ])
      })
    })

    describe("when the line doesn't match any patterns", () => {
      it("returns the entire line as a single simple token with the grammar's scope", () => {
        const textGrammar = registry.grammarForScopeName('text.plain')
        const {line, tags} = textGrammar.tokenizeLine('abc def')
        const tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 1)
      })
    })

    describe('when the line matches multiple patterns', () => {
      it("returns multiple tokens, filling in regions that don't match patterns with tokens in the grammar's global scope", () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine(' return new foo.bar.Baz ')

        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: ' ', scopes: ['source.coffee']},
          {value: 'return', scopes: ['source.coffee', 'keyword.control.coffee']},
          {value: ' ', scopes: ['source.coffee']},
          {value: 'new', scopes: ['source.coffee', 'meta.class.instance.constructor', 'keyword.operator.new.coffee']},
          {value: ' ', scopes: ['source.coffee', 'meta.class.instance.constructor']},
          {value: 'foo.bar.Baz', scopes: ['source.coffee', 'meta.class.instance.constructor', 'entity.name.type.instance.coffee']},
          {value: ' ', scopes: ['source.coffee']}
        ])
      })
    })

    describe('when the line matches a pattern with optional capture groups', () => {
      it('only returns tokens for capture groups that matched', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('class Quicksort')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens.length, 3)
        assert.equal(tokens[0].value, 'class')
        assert.equal(tokens[1].value, ' ')
        assert.equal(tokens[2].value, 'Quicksort')
      })
    })

    describe('when the line matches a rule with nested capture groups and lookahead capture groups beyond the scope of the overall match', () => {
      it('creates distinct tokens for nested captures and does not return tokens beyond the scope of the overall capture', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('  destroy: ->')

        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: '  ', scopes: ['source.coffee']},
          {value: 'destro', scopes: ['source.coffee', 'meta.function.coffee', 'entity.name.function.coffee']},
          // duplicated scope looks wrong, but textmate yields the same behavior. probably a quirk in the coffee grammar.
          {value: 'y', scopes: ['source.coffee', 'meta.function.coffee', 'entity.name.function.coffee', 'entity.name.function.coffee']},
          {value: ':', scopes: ['source.coffee', 'keyword.operator.coffee']},
          {value: ' ', scopes: ['source.coffee']},
          {value: '->', scopes: ['source.coffee', 'storage.type.function.coffee']}
        ])
      })
    })

    describe('when the line matches a pattern that includes a rule', () => {
      it('returns tokens based on the included rule', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('7777777')
        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: '7777777', scopes: ['source.coffee', 'constant.numeric.coffee']}
        ])
      })
    })

    describe('when the line is an interpolated string', () => {
      it('returns the correct tokens', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('"the value is #{@x} my friend"')

        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: '"', scopes: ['source.coffee', 'string.quoted.double.coffee', 'punctuation.definition.string.begin.coffee']},
          {value: 'the value is ', scopes: ['source.coffee', 'string.quoted.double.coffee']},
          {value: '#{', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'punctuation.section.embedded.coffee']},
          {value: '@x', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'variable.other.readwrite.instance.coffee']},
          {value: '}', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'punctuation.section.embedded.coffee']},
          {value: ' my friend', scopes: ['source.coffee', 'string.quoted.double.coffee']},
          {value: '"', scopes: ['source.coffee', 'string.quoted.double.coffee', 'punctuation.definition.string.end.coffee']}
        ])
      })
    })

    describe('when the line has an interpolated string inside an interpolated string', () => {
      it('returns the correct tokens', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('"#{"#{@x}"}"')

        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: '"', scopes: ['source.coffee', 'string.quoted.double.coffee', 'punctuation.definition.string.begin.coffee']},
          {value: '#{', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'punctuation.section.embedded.coffee']},
          {value: '"', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'string.quoted.double.coffee', 'punctuation.definition.string.begin.coffee']},
          {value: '#{', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'punctuation.section.embedded.coffee']},
          {value: '@x', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'variable.other.readwrite.instance.coffee']},
          {value: '}', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'punctuation.section.embedded.coffee']},
          {value: '"', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'string.quoted.double.coffee', 'punctuation.definition.string.end.coffee']},
          {value: '}', scopes: ['source.coffee', 'string.quoted.double.coffee', 'source.coffee.embedded.source', 'punctuation.section.embedded.coffee']},
          {value: '"', scopes: ['source.coffee', 'string.quoted.double.coffee', 'punctuation.definition.string.end.coffee']}
        ])
      })
    })

    describe('when the line is empty', () => {
      it('returns a single token which has the global scope', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine('')
        assert.deepEqual(registry.decodeTokens(line, tags), [{value: '', scopes: ['source.coffee']}])
      })
    })

    describe('when the line matches no patterns', () => {
      it('does not infinitely loop', () => {
        grammar = registry.grammarForScopeName('text.plain')
        const {line, tags} = grammar.tokenizeLine('hoo')
        assert.deepEqual(registry.decodeTokens(line, tags), [{value: 'hoo', scopes: ['text.plain', 'meta.paragraph.text']}])
      })
    })

    describe("when the line matches a pattern with a 'contentName'", () => {
      it('creates tokens using the content of contentName as the token name', () => {
        grammar = registry.grammarForScopeName('text.plain')
        let {line, tags} = grammar.tokenizeLine('ok, cool')
        assert.deepEqual(registry.decodeTokens(line, tags), [{value: 'ok, cool', scopes: ['text.plain', 'meta.paragraph.text']}])

        grammar = registry.grammarForScopeName('text.plain');
        ({line, tags} = grammar.tokenizeLine(' ok, cool'))

        assert.deepEqual(registry.decodeTokens(line, tags), [
          {value: ' ', scopes: ['text.plain']},
          {value: 'ok, cool', scopes: ['text.plain', 'meta.paragraph.text']}
        ])

        loadGrammarSync('content-name.json')

        grammar = registry.grammarForScopeName('source.test')
        const lines = grammar.tokenizeLines('#if\ntest\n#endif')

        assert.equal(lines[0].length, 1)
        assert.equal(lines[0][0].value, '#if')
        assert.deepEqual(lines[0][0].scopes, ['source.test', 'pre'])

        assert.equal(lines[1].length, 1)
        assert.equal(lines[1][0].value, 'test')
        assert.deepEqual(lines[1][0].scopes, ['source.test', 'pre', 'nested'])

        assert.equal(lines[2].length, 2)
        assert.equal(lines[2][0].value, '#endif')
        assert.deepEqual(lines[2][0].scopes, ['source.test', 'pre'])
        assert.equal(lines[2][1].value, '')
        assert.deepEqual(lines[2][1].scopes, ['source.test', 'all']);

        ({line, tags} = grammar.tokenizeLine('test'))
        let tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 1)
        assert.equal(tokens[0].value, 'test')
        assert.deepEqual(tokens[0].scopes, ['source.test', 'all', 'middle']);

        ({line, tags} = grammar.tokenizeLine(' test'))
        tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 2)
        assert.equal(tokens[0].value, ' ')
        assert.deepEqual(tokens[0].scopes, ['source.test', 'all'])
        assert.equal(tokens[1].value, 'test')
        assert.deepEqual(tokens[1].scopes, ['source.test', 'all', 'middle'])
      })
    })

    describe('when the line matches a pattern with no `name` or `contentName`', () => {
      it('creates tokens without adding a new scope', () => {
        grammar = registry.grammarForScopeName('source.ruby')
        const {line, tags} = grammar.tokenizeLine('%w|oh \\look|')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens.length, 5)
        assert.deepEqual(tokens[0], {value: '%w|', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby', 'punctuation.definition.string.begin.ruby']})
        assert.deepEqual(tokens[1], {value: 'oh ', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby']})
        assert.deepEqual(tokens[2], {value: '\\l', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby']})
        assert.deepEqual(tokens[3], {value: 'ook', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby']})
      })
    })

    describe('when the line matches a begin/end pattern', () => {
      it('returns tokens based on the beginCaptures, endCaptures and the child scope', () => {
        grammar = registry.grammarForScopeName('source.coffee')
        const {line, tags} = grammar.tokenizeLine("'''single-quoted heredoc'''")
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens.length, 3)

        assert.deepEqual(tokens[0], {value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.begin.coffee']})
        assert.deepEqual(tokens[1], {value: 'single-quoted heredoc', scopes: ['source.coffee', 'string.quoted.heredoc.coffee']})
        assert.deepEqual(tokens[2], {value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.end.coffee']})
      })

      describe('when the pattern spans multiple lines', () => {
        it('uses the ruleStack returned by the first line to parse the second line', () => {
          let line2, tags2
          grammar = registry.grammarForScopeName('source.coffee')
          let {line: line1, tags: tags1, ruleStack} = grammar.tokenizeLine("'''single-quoted");
          ({line: line2, tags: tags2, ruleStack} = grammar.tokenizeLine("heredoc'''", ruleStack))

          const scopes = []
          const firstTokens = registry.decodeTokens(line1, tags1, scopes)
          const secondTokens = registry.decodeTokens(line2, tags2, scopes)

          assert.equal(firstTokens.length, 2)
          assert.equal(secondTokens.length, 2)

          assert.deepEqual(firstTokens[0], {value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.begin.coffee']})
          assert.deepEqual(firstTokens[1], {value: 'single-quoted', scopes: ['source.coffee', 'string.quoted.heredoc.coffee']})

          assert.deepEqual(secondTokens[0], {value: 'heredoc', scopes: ['source.coffee', 'string.quoted.heredoc.coffee']})
          assert.deepEqual(secondTokens[1], {value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.end.coffee']})
        })
      })

      describe('when the pattern contains sub-patterns', () => {
        it('returns tokens within the begin/end scope based on the sub-patterns', () => {
          grammar = registry.grammarForScopeName('source.coffee')
          const {line, tags} = grammar.tokenizeLine('"""heredoc with character escape \\t"""')
          const tokens = registry.decodeTokens(line, tags)

          assert.equal(tokens.length, 4)

          assert.deepEqual(tokens[0], {value: '"""', scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee', 'punctuation.definition.string.begin.coffee']})
          assert.deepEqual(tokens[1], {value: 'heredoc with character escape ', scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee']})
          assert.deepEqual(tokens[2], {value: '\\t', scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee', 'constant.character.escape.coffee']})
          assert.deepEqual(tokens[3], {value: '"""', scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee', 'punctuation.definition.string.end.coffee']})
        })
      })

      describe('when applyEndPatternLast flag is set in a pattern', () => {
        it('applies end pattern after the other patterns', () => {
          grammar = loadGrammarSync('apply-end-pattern-last.cson')
          const lines = grammar.tokenizeLines(`\
last
{ some }excentricSyntax }

first
{ some }excentricSyntax }\
`
          )

          assert.deepEqual(lines[1][2], {value: '}excentricSyntax', scopes: ['source.apply-end-pattern-last', 'end-pattern-last-env', 'scope', 'excentric']})
          assert.deepEqual(lines[4][2], {value: '}', scopes: ['source.apply-end-pattern-last', 'normal-env', 'scope']})
          assert.deepEqual(lines[4][3], {value: 'excentricSyntax }', scopes: ['source.apply-end-pattern-last', 'normal-env']})
        })
      })

      describe('when the end pattern contains a back reference', () => {
        it('constructs the end rule based on its back-references to captures in the begin rule', () => {
          grammar = registry.grammarForScopeName('source.ruby')
          const {line, tags} = grammar.tokenizeLine('%w|oh|,')
          const tokens = registry.decodeTokens(line, tags)

          assert.equal(tokens.length, 4)
          assert.deepEqual(tokens[0], {value: '%w|', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby', 'punctuation.definition.string.begin.ruby']})
          assert.deepEqual(tokens[1], {value: 'oh', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby']})
          assert.deepEqual(tokens[2], {value: '|', scopes: ['source.ruby', 'string.quoted.other.literal.lower.ruby', 'punctuation.definition.string.end.ruby']})
          assert.deepEqual(tokens[3], {value: ',', scopes: ['source.ruby', 'punctuation.separator.object.ruby']})
        })

        it('allows the rule containing that end pattern to be pushed to the stack multiple times', () => {
          grammar = registry.grammarForScopeName('source.ruby')
          const {line, tags} = grammar.tokenizeLine('%Q+matz had some #{%Q-crazy ideas-} for ruby syntax+ # damn.')
          const tokens = registry.decodeTokens(line, tags)

          assert.deepEqual(tokens[0], {value: '%Q+', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'punctuation.definition.string.begin.ruby']})
          assert.deepEqual(tokens[1], {value: 'matz had some ', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby']})
          assert.deepEqual(tokens[2], {value: '#{', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'meta.embedded.line.ruby', 'punctuation.section.embedded.begin.ruby']})
          assert.deepEqual(tokens[3], {value: '%Q-', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'meta.embedded.line.ruby', 'source.ruby', 'string.quoted.other.literal.upper.ruby', 'punctuation.definition.string.begin.ruby']})
          assert.deepEqual(tokens[4], {value: 'crazy ideas', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'meta.embedded.line.ruby', 'source.ruby', 'string.quoted.other.literal.upper.ruby']})
          assert.deepEqual(tokens[5], {value: '-', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'meta.embedded.line.ruby', 'source.ruby', 'string.quoted.other.literal.upper.ruby', 'punctuation.definition.string.end.ruby']})
          assert.deepEqual(tokens[6], {value: '}', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'meta.embedded.line.ruby', 'punctuation.section.embedded.end.ruby', 'source.ruby']})
          assert.deepEqual(tokens[7], {value: ' for ruby syntax', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby']})
          assert.deepEqual(tokens[8], {value: '+', scopes: ['source.ruby', 'string.quoted.other.literal.upper.ruby', 'punctuation.definition.string.end.ruby']})
          assert.deepEqual(tokens[9], {value: ' ', scopes: ['source.ruby']})
          assert.deepEqual(tokens[10], {value: '#', scopes: ['source.ruby', 'comment.line.number-sign.ruby', 'punctuation.definition.comment.ruby']})
          assert.deepEqual(tokens[11], {value: ' damn.', scopes: ['source.ruby', 'comment.line.number-sign.ruby']})
        })
      })

      describe('when the pattern includes rules from another grammar', () => {
        describe('when a grammar matching the desired scope is available', () => {
          it("parses tokens inside the begin/end patterns based on the included grammar's rules", () => {
            loadGrammarSync('html-rails.json')
            loadGrammarSync('ruby-on-rails.json')

            grammar = registry.grammarForScopeName('text.html.ruby')
            const {line, tags} = grammar.tokenizeLine("<div class='name'><%= User.find(2).full_name %></div>")
            const tokens = registry.decodeTokens(line, tags)

            assert.deepEqual(tokens[0], {value: '<', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'punctuation.definition.tag.begin.html']})
            assert.deepEqual(tokens[1], {value: 'div', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'entity.name.tag.block.any.html']})
            assert.deepEqual(tokens[2], {value: ' ', scopes: ['text.html.ruby', 'meta.tag.block.any.html']})
            assert.deepEqual(tokens[3], {value: 'class', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'entity.other.attribute-name.html']})
            assert.deepEqual(tokens[4], {value: '=', scopes: ['text.html.ruby', 'meta.tag.block.any.html']})
            assert.deepEqual(tokens[5], {value: '\'', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'string.quoted.single.html', 'punctuation.definition.string.begin.html']})
            assert.deepEqual(tokens[6], {value: 'name', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'string.quoted.single.html']})
            assert.deepEqual(tokens[7], {value: '\'', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'string.quoted.single.html', 'punctuation.definition.string.end.html']})
            assert.deepEqual(tokens[8], {value: '>', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'punctuation.definition.tag.end.html']})
            assert.deepEqual(tokens[9], {value: '<%=', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.section.embedded.ruby']})
            assert.deepEqual(tokens[10], {value: ' ', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html']})
            assert.deepEqual(tokens[11], {value: 'User', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'support.class.ruby']})
            assert.deepEqual(tokens[12], {value: '.', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.separator.method.ruby']})
            assert.deepEqual(tokens[13], {value: 'find', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html']})
            assert.deepEqual(tokens[14], {value: '(', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.section.function.ruby']})
            assert.deepEqual(tokens[15], {value: '2', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'constant.numeric.ruby']})
            assert.deepEqual(tokens[16], {value: ')', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.section.function.ruby']})
            assert.deepEqual(tokens[17], {value: '.', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.separator.method.ruby']})
            assert.deepEqual(tokens[18], {value: 'full_name ', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html']})
            assert.deepEqual(tokens[19], {value: '%>', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.section.embedded.ruby']})
            assert.deepEqual(tokens[20], {value: '</', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'punctuation.definition.tag.begin.html']})
            assert.deepEqual(tokens[21], {value: 'div', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'entity.name.tag.block.any.html']})
            assert.deepEqual(tokens[22], {value: '>', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'punctuation.definition.tag.end.html']})
          })

          it('updates the grammar if the included grammar is updated later', () => {
            loadGrammarSync('html-rails.json')
            loadGrammarSync('ruby-on-rails.json')

            grammar = registry.grammarForScopeName('text.html.ruby')
            const grammarUpdatedHandler = sandbox.spy()
            grammar.onDidUpdate(grammarUpdatedHandler)

            let {line, tags} = grammar.tokenizeLine("<div class='name'><% <<-SQL select * from users;")
            let tokens = registry.decodeTokens(line, tags)
            assert.equal(tokens[12].value, ' select * from users;')

            loadGrammarSync('sql.json')
            assert.equal(grammarUpdatedHandler.called, true);
            ({line, tags} = grammar.tokenizeLine("<div class='name'><% <<-SQL select * from users;"))
            tokens = registry.decodeTokens(line, tags)
            assert.equal(tokens[12].value, ' ')
            assert.equal(tokens[13].value, 'select')
          })

          it('supports including repository rules from the other grammar', () => {
            loadGrammarSync('include-external-repository-rule.cson')
            grammar = registry.grammarForScopeName('test.include-external-repository-rule')
            const {line, tags} = grammar.tokenizeLine('enumerate')
            const tokens = registry.decodeTokens(line, tags)
            assert.deepEqual(tokens[0], {value: 'enumerate', scopes: ['test.include-external-repository-rule', 'support.function.builtin.python']})

            const updateCallback = sandbox.spy()
            grammar.onDidUpdate(updateCallback)
            assert.equal(grammar.grammarUpdated('source.python'), true)
            assert.equal(grammar.grammarUpdated('not.included'), false)
            assert.equal(updateCallback.calledOnce, true)
          })
        })

        describe('when a grammar matching the desired scope is unavailable', () => {
          it('updates the grammar if a matching grammar is added later', () => {
            registry.removeGrammarForScopeName('text.html.basic')
            loadGrammarSync('html-rails.json')
            loadGrammarSync('ruby-on-rails.json')

            grammar = registry.grammarForScopeName('text.html.ruby')
            let {line, tags} = grammar.tokenizeLine("<div class='name'><%= User.find(2).full_name %></div>")
            let tokens = registry.decodeTokens(line, tags)
            assert.deepEqual(tokens[0], {value: "<div class='name'>", scopes: ['text.html.ruby']})
            assert.deepEqual(tokens[1], {value: '<%=', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.section.embedded.ruby']})
            assert.deepEqual(tokens[2], {value: ' ', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html']})
            assert.deepEqual(tokens[3], {value: 'User', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'support.class.ruby']})

            loadGrammarSync('html.json');
            ({line, tags} = grammar.tokenizeLine("<div class='name'><%= User.find(2).full_name %></div>"))
            tokens = registry.decodeTokens(line, tags)
            assert.deepEqual(tokens[0], {value: '<', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'punctuation.definition.tag.begin.html']})
            assert.deepEqual(tokens[1], {value: 'div', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'entity.name.tag.block.any.html']})
            assert.deepEqual(tokens[2], {value: ' ', scopes: ['text.html.ruby', 'meta.tag.block.any.html']})
            assert.deepEqual(tokens[3], {value: 'class', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'entity.other.attribute-name.html']})
            assert.deepEqual(tokens[4], {value: '=', scopes: ['text.html.ruby', 'meta.tag.block.any.html']})
            assert.deepEqual(tokens[5], {value: '\'', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'string.quoted.single.html', 'punctuation.definition.string.begin.html']})
            assert.deepEqual(tokens[6], {value: 'name', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'string.quoted.single.html']})
            assert.deepEqual(tokens[7], {value: '\'', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'string.quoted.single.html', 'punctuation.definition.string.end.html']})
            assert.deepEqual(tokens[8], {value: '>', scopes: ['text.html.ruby', 'meta.tag.block.any.html', 'punctuation.definition.tag.end.html']})
            assert.deepEqual(tokens[9], {value: '<%=', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html', 'punctuation.section.embedded.ruby']})
            assert.deepEqual(tokens[10], {value: ' ', scopes: ['text.html.ruby', 'source.ruby.rails.embedded.html']})
          })
        })
      })
    })

    it('can parse a grammar with newline characters in its regular expressions (regression)', () => {
      grammar = loadGrammarSync('imaginary.cson')
      const {line, tags, ruleStack} = grammar.tokenizeLine('// a singleLineComment')
      const tokens = registry.decodeTokens(line, tags)
      assert.equal(ruleStack.length, 1)
      assert.equal(ruleStack[0].scopeName, 'source.imaginaryLanguage')

      assert.equal(tokens.length, 3)
      assert.equal(tokens[0].value, '//')
      assert.equal(tokens[1].value, ' a singleLineComment')
      assert.equal(tokens[2].value, '')
    })

    it('can parse multiline text using a grammar containing patterns with newlines', () => {
      grammar = loadGrammarSync('multiline.cson')
      const lines = grammar.tokenizeLines('Xy\\\nzX')

      // Line 0
      assert.deepEqual(lines[0][0], {
        value: 'X',
        scopes: ['source.multilineLanguage', 'outside-x', 'start']})

      assert.deepEqual(lines[0][1], {
        value: 'y',
        scopes: ['source.multilineLanguage', 'outside-x']})

      assert.deepEqual(lines[0][2], {
        value: '\\',
        scopes: ['source.multilineLanguage', 'outside-x', 'inside-x']})

      assert.isUndefined(lines[0][3])

      // Line 1
      assert.deepEqual(lines[1][0], {
        value: 'z',
        scopes: ['source.multilineLanguage', 'outside-x']})

      assert.deepEqual(lines[1][1], {
        value: 'X',
        scopes: ['source.multilineLanguage', 'outside-x', 'end']})

      assert.isUndefined(lines[1][2])
    })

    it('does not loop infinitely (regression)', () => {
      grammar = registry.grammarForScopeName('source.js')
      let {ruleStack} = grammar.tokenizeLine('// line comment')
      grammar.tokenizeLine(' // second line comment with a single leading space', ruleStack)
    })

    describe('when inside a C block', () => {
      beforeEach(() => {
        loadGrammarSync('c.json')
        loadGrammarSync('c-plus-plus.json')
        grammar = registry.grammarForScopeName('source.c')
      })

      it('correctly parses a method. (regression)', () => {
        const {line, tags} = grammar.tokenizeLine('if(1){m()}')
        const tokens = registry.decodeTokens(line, tags)
        assert.deepEqual(tokens[5], {value: 'm', scopes: ['source.c', 'meta.block.c', 'meta.function-call.c', 'support.function.any-method.c']})
      })

      it('correctly parses nested blocks. (regression)', () => {
        const {line, tags} = grammar.tokenizeLine('if(1){if(1){m()}}')
        const tokens = registry.decodeTokens(line, tags)
        assert.deepEqual(tokens[5], {value: 'if', scopes: ['source.c', 'meta.block.c', 'keyword.control.c']})
        assert.deepEqual(tokens[10], {value: 'm', scopes: ['source.c', 'meta.block.c', 'meta.block.c', 'meta.function-call.c', 'support.function.any-method.c']})
      })
    })

    describe('when the grammar can infinitely loop over a line', () =>
      it('aborts tokenization', () => {
        sandbox.stub(console, 'error')
        grammar = loadGrammarSync('infinite-loop.cson')
        const {line, tags} = grammar.tokenizeLine('abc')
        const scopes = []
        const tokens = registry.decodeTokens(line, tags, scopes)
        assert.equal(tokens[0].value, 'a')
        assert.equal(tokens[1].value, 'bc')
        assert.deepEqual(scopes, [registry.startIdForScope(grammar.scopeName)])
        assert.equal(console.error.called, true)
      })
    )

    describe('when a grammar has a pattern that has back references in the match value', () => {
      it('does not special handle the back references and instead allows oniguruma to resolve them', () => {
        loadGrammarSync('scss.json')
        grammar = registry.grammarForScopeName('source.css.scss')
        const {line, tags} = grammar.tokenizeLine('@mixin x() { -moz-selector: whatever; }')
        const tokens = registry.decodeTokens(line, tags)
        assert.deepEqual(tokens[9], {value: '-moz-selector', scopes: ['source.css.scss', 'meta.property-list.scss', 'meta.property-name.scss']})
      })
    })

    describe('when a line has more tokens than `maxTokensPerLine`', () => {
      it('creates a final token with the remaining text and resets the ruleStack to match the begining of the line', () => {
        grammar = registry.grammarForScopeName('source.js')
        const originalRuleStack = grammar.tokenizeLine('').ruleStack
        sandbox.stub(grammar, 'getMaxTokensPerLine').callsFake(() => 5)
        const {line, tags, ruleStack} = grammar.tokenizeLine('var x = /[a-z]/;', originalRuleStack)
        const scopes = []
        const tokens = registry.decodeTokens(line, tags, scopes)
        assert.equal(tokens.length, 6)
        assert.equal(tokens[5].value, '[a-z]/;')
        assert.deepEqual(ruleStack, originalRuleStack)
        assert.notEqual(ruleStack, originalRuleStack)
        assert.equal(scopes.length, 0)
      })
    })

    describe('when a grammar has a capture with patterns', () => {
      it("matches the patterns and includes the scope specified as the pattern's match name", () => {
        grammar = registry.grammarForScopeName('text.html.php')
        const {line, tags} = grammar.tokenizeLine('<?php public final function meth() {} ?>')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[2].value, 'public')
        assert.deepEqual(tokens[2].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'storage.modifier.php'])

        assert.equal(tokens[3].value, ' ')
        assert.deepEqual(tokens[3].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php'])

        assert.equal(tokens[4].value, 'final')
        assert.deepEqual(tokens[4].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'storage.modifier.php'])

        assert.equal(tokens[5].value, ' ')
        assert.deepEqual(tokens[5].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php'])

        assert.equal(tokens[6].value, 'function')
        assert.deepEqual(tokens[6].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'storage.type.function.php'])
      })

      it('ignores child captures of a capture with patterns', () => {
        grammar = loadGrammarSync('nested-captures.cson')
        const {line, tags} = grammar.tokenizeLine('ab')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[0].value, 'ab')
        assert.deepEqual(tokens[0].scopes, ['nested', 'text', 'a'])
      })
    })

    describe('when the grammar has injections', () => {
      it('correctly includes the injected patterns when tokenizing', () => {
        grammar = registry.grammarForScopeName('text.html.php')
        const {line, tags} = grammar.tokenizeLine('<div><?php function hello() {} ?></div>')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[3].value, '<?php')
        assert.deepEqual(tokens[3].scopes, ['text.html.php', 'meta.embedded.line.php', 'punctuation.section.embedded.begin.php'])

        assert.equal(tokens[5].value, 'function')
        assert.deepEqual(tokens[5].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'storage.type.function.php'])

        assert.equal(tokens[7].value, 'hello')
        assert.deepEqual(tokens[7].scopes, ['text.html.php', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'entity.name.function.php'])

        assert.equal(tokens[14].value, '?')
        assert.deepEqual(tokens[14].scopes, ['text.html.php', 'meta.embedded.line.php', 'punctuation.section.embedded.end.php', 'source.php'])

        assert.equal(tokens[15].value, '>')
        assert.deepEqual(tokens[15].scopes, ['text.html.php', 'meta.embedded.line.php', 'punctuation.section.embedded.end.php'])

        assert.equal(tokens[16].value, '</')
        assert.deepEqual(tokens[16].scopes, ['text.html.php', 'meta.tag.block.any.html', 'punctuation.definition.tag.begin.html'])

        assert.equal(tokens[17].value, 'div')
        assert.deepEqual(tokens[17].scopes, ['text.html.php', 'meta.tag.block.any.html', 'entity.name.tag.block.any.html'])
      })

      it('gives lower priority to them than other matches', () => {
        loadGrammarSync('php2.json')
        grammar = registry.grammarForScopeName('text.html.php2')
        // PHP2 is a modified PHP grammar which has a regular source.js.embedded.html injection
        const {line, tags} = grammar.tokenizeLine('<script><?php function hello() {} ?></script>')
        const tokens = registry.decodeTokens(line, tags)

        assert.notEqual(tokens[3].value, '<?php')
        assert.equal(tokens[3].value, '<')
        assert.deepEqual(tokens[3].scopes, ['text.html.php2', 'source.js.embedded.html', 'keyword.operator.js'])
      })
    })

    describe('when the grammar has prefixed injections', () => {
      it('correctly prioritizes them when tokenizing', () => {
        grammar = registry.grammarForScopeName('text.html.php')
        // PHP has a L:source.js.embedded.html injection
        const {line, tags} = grammar.tokenizeLine('<script><?php function hello() {} ?></script>')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[3].value, '<?php')
        assert.deepEqual(tokens[3].scopes, ['text.html.php', 'source.js.embedded.html', 'meta.embedded.line.php', 'punctuation.section.embedded.begin.php'])

        assert.equal(tokens[5].value, 'function')
        assert.deepEqual(tokens[5].scopes, ['text.html.php', 'source.js.embedded.html', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'storage.type.function.php'])

        assert.equal(tokens[7].value, 'hello')
        assert.deepEqual(tokens[7].scopes, ['text.html.php', 'source.js.embedded.html', 'meta.embedded.line.php', 'source.php', 'meta.function.php', 'entity.name.function.php'])

        assert.equal(tokens[14].value, '?')
        assert.deepEqual(tokens[14].scopes, ['text.html.php', 'source.js.embedded.html', 'meta.embedded.line.php', 'punctuation.section.embedded.end.php', 'source.php'])

        assert.equal(tokens[15].value, '>')
        assert.deepEqual(tokens[15].scopes, ['text.html.php', 'source.js.embedded.html', 'meta.embedded.line.php', 'punctuation.section.embedded.end.php'])

        assert.equal(tokens[16].value, '</')
        assert.deepEqual(tokens[16].scopes, ['text.html.php', 'source.js.embedded.html', 'punctuation.definition.tag.html'])

        assert.equal(tokens[17].value, 'script')
        assert.deepEqual(tokens[17].scopes, ['text.html.php', 'source.js.embedded.html', 'entity.name.tag.script.html'])
      })
    })

    describe('when the grammar has an injection selector', () => {
      it("includes the grammar's patterns when the selector matches the current scope in other grammars", () => {
        loadGrammarSync('hyperlink.json')
        grammar = registry.grammarForScopeName('source.js')
        const {line, tags} = grammar.tokenizeLine('var i; // http://github.com')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[0].value, 'var')
        assert.deepEqual(tokens[0].scopes, ['source.js', 'storage.modifier.js'])

        assert.equal(tokens[6].value, 'http://github.com')
        assert.deepEqual(tokens[6].scopes, ['source.js', 'comment.line.double-slash.js', 'markup.underline.link.http.hyperlink'])
      })

      it('gives lower priority to them than other matches', () => {
        loadGrammarSync('normal-injection-selector.cson')
        grammar = registry.grammarForScopeName('source.js')
        const {line, tags} = grammar.tokenizeLine('<!--')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[0].value, '<!--')
        assert.notDeepEqual(tokens[0].scopes, ['source.js', 'should-not-be-matched.normal.injection-selector'])
        assert.deepEqual(tokens[0].scopes, ['source.js', 'comment.block.html.js', 'punctuation.definition.comment.html.js'])
      })
    })

    describe('when the grammar has a prefixed injection selector', () => {
      it('correctly prioritizes them when tokenizing', () => {
        loadGrammarSync('prefixed-injection-selector.cson')
        grammar = registry.grammarForScopeName('source.js')
        const {line, tags} = grammar.tokenizeLine('<!--')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[0].value, '<!--')
        assert.notDeepEqual(tokens[0].scopes, ['source.js', 'comment.block.html.js', 'punctuation.definition.comment.html.js'])
        assert.deepEqual(tokens[0].scopes, ['source.js', 'should-be-matched.prefixed.injection-selector'])
      })
    })

    describe("when the grammar's pattern name has a group number in it", () => {
      it('replaces the group number with the matched captured text', () => {
        grammar = loadGrammarSync('hyperlink.json')
        const {line, tags} = grammar.tokenizeLine('https://github.com')
        const tokens = registry.decodeTokens(line, tags)
        assert.deepEqual(tokens[0].scopes, ['text.hyperlink', 'markup.underline.link.https.hyperlink'])
      })
    })

    describe("when the position doesn't advance and rule includes $self and matches itself", () => {
      it('tokenizes the entire line using the rule', () => {
        grammar = loadGrammarSync('forever.cson')
        const {line, tags} = grammar.tokenizeLine('forever and ever')
        const tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 1)
        assert.equal(tokens[0].value, 'forever and ever')
        assert.deepEqual(tokens[0].scopes, ['source.forever', 'text'])
      })
    })

    describe('${capture:/command} style pattern names', () => { // eslint-disable-line no-template-curly-in-string
      it('replaces the number with the capture group and translates the text', () => {
        loadGrammarSync('todo.json')
        grammar = registry.grammarForScopeName('source.ruby')
        const {line, tags} = grammar.tokenizeLine('# TODO be nicer')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[2].value, 'TODO')
        assert.deepEqual(tokens[2].scopes, ['source.ruby', 'comment.line.number-sign.ruby', 'storage.type.class.todo'])
      })
    })

    describe('$number style pattern names', () => {
      it('replaces the number with the capture group and translates the text', () => {
        loadGrammarSync('makefile.json')
        grammar = registry.grammarForScopeName('source.makefile')
        let {line, tags} = grammar.tokenizeLine('ifeq')
        let tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 1)
        assert.equal(tokens[0].value, 'ifeq')
        assert.deepEqual(tokens[0].scopes, ['source.makefile', 'meta.scope.conditional.makefile', 'keyword.control.ifeq.makefile']);

        ({line, tags} = grammar.tokenizeLine('ifeq ('))
        tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 2)
        assert.equal(tokens[0].value, 'ifeq')
        assert.deepEqual(tokens[0].scopes, ['source.makefile', 'meta.scope.conditional.makefile', 'keyword.control.ifeq.makefile'])
        assert.equal(tokens[1].value, ' (')
        assert.deepEqual(tokens[1].scopes, ['source.makefile', 'meta.scope.conditional.makefile', 'meta.scope.condition.makefile'])
      })

      it('removes leading dot characters from the replaced capture index placeholder', () => {
        loadGrammarSync('makefile.json')
        grammar = registry.grammarForScopeName('source.makefile')
        const {line, tags} = grammar.tokenizeLine('.PHONY:')
        const tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 2)
        assert.deepEqual(tokens[0].scopes, ['source.makefile', 'meta.scope.target.makefile', 'support.function.target.PHONY.makefile'])
        assert.equal(tokens[0].value, '.PHONY')
      })

      it('replaces all occurences of capture index placeholders', () => {
        loadGrammarSync('scope-names-with-placeholders.cson')
        grammar = registry.grammarForScopeName('scope-names-with-placeholders')
        const {line, tags} = grammar.tokenizeLine('a b')
        const tokens = registry.decodeTokens(line, tags)
        assert.equal(tokens.length, 1)
        assert.equal(tokens[0].value, 'a b')
        assert.deepEqual(tokens[0].scopes, ['scope-names-with-placeholders', 'a.b'])
      })
    })
  })

  describe('language-specific integration tests', () => {
    let lines = null

    describe('Git commit messages', () => {
      beforeEach(() => {
        grammar = loadGrammarSync('git-commit.json')
        lines = grammar.tokenizeLines(`\
longggggggggggggggggggggggggggggggggggggggggggggggg
# Please enter the commit message for your changes. Lines starting\
`
        )
      })

      it('correctly parses a long line', () => {
        const tokens = lines[0]
        assert.equal(tokens[0].value, 'longggggggggggggggggggggggggggggggggggggggggggggggg')
        assert.deepEqual(tokens[0].scopes, ['text.git-commit', 'meta.scope.message.git-commit', 'invalid.deprecated.line-too-long.git-commit'])
      })

      it('correctly parses the number sign of the first comment line', () => {
        const tokens = lines[1]
        assert.equal(tokens[0].value, '#')
        assert.deepEqual(tokens[0].scopes, ['text.git-commit', 'meta.scope.metadata.git-commit', 'comment.line.number-sign.git-commit', 'punctuation.definition.comment.git-commit'])
      })
    })

    describe('C++', () => {
      beforeEach(() => {
        loadGrammarSync('c.json')
        grammar = loadGrammarSync('c-plus-plus.json')
        lines = grammar.tokenizeLines(`\
#include "a.h"
#include "b.h"\
`
        )
      })

      it('correctly parses the first include line', () => {
        const tokens = lines[0]
        assert.equal(tokens[0].value, '#')
        assert.deepEqual(tokens[0].scopes, ['source.c++', 'meta.preprocessor.c.include'])
        assert.equal(tokens[1].value, 'include')
        assert.deepEqual(tokens[1].scopes, ['source.c++', 'meta.preprocessor.c.include', 'keyword.control.import.include.c'])
      })

      it('correctly parses the second include line', () => {
        const tokens = lines[1]
        assert.equal(tokens[0].value, '#')
        assert.deepEqual(tokens[0].scopes, ['source.c++', 'meta.preprocessor.c.include'])
        assert.equal(tokens[1].value, 'include')
        assert.deepEqual(tokens[1].scopes, ['source.c++', 'meta.preprocessor.c.include', 'keyword.control.import.include.c'])
      })
    })

    describe('Ruby', () => {
      beforeEach(() => {
        grammar = registry.grammarForScopeName('source.ruby')
        lines = grammar.tokenizeLines(`\
a = {
  "b" => "c",
}\
`
        )
      })

      it("doesn't loop infinitely (regression)", () => {
        assert.equal(lines[0].map(object => object['value']).join(''), 'a = {')
        assert.equal(lines[1].map(object => object['value']).join(''), '  "b" => "c",')
        assert.equal(lines[2].map(object => object['value']).join(''), '}')
        assert.isUndefined(lines[3])
      })
    })

    describe('Objective-C', () => {
      beforeEach(() => {
        loadGrammarSync('c.json')
        loadGrammarSync('c-plus-plus.json')
        loadGrammarSync('objective-c.json')
        grammar = loadGrammarSync('objective-c-plus-plus.json')
        lines = grammar.tokenizeLines(`\
void test() {
NSString *a = @"a\\nb";
}\
`
        )
      })

      it('correctly parses variable type when it is a built-in Cocoa class', () => {
        const tokens = lines[1]
        assert.equal(tokens[0].value, 'NSString')
        assert.deepEqual(tokens[0].scopes, ['source.objc++', 'meta.function.c', 'meta.block.c', 'support.class.cocoa'])
      })

      it('correctly parses the semicolon at the end of the line', () => {
        const tokens = lines[1]
        const lastToken = tokens[tokens.length - 1]
        assert.equal(lastToken.value, ';')
        assert.deepEqual(lastToken.scopes, ['source.objc++', 'meta.function.c', 'meta.block.c'])
      })

      it('correctly parses the string characters before the escaped character', () => {
        const tokens = lines[1]
        assert.equal(tokens[2].value, '@"')
        assert.deepEqual(tokens[2].scopes, ['source.objc++', 'meta.function.c', 'meta.block.c', 'string.quoted.double.objc', 'punctuation.definition.string.begin.objc'])
      })
    })

    describe('Java', () => {
      beforeEach(() => {
        loadGrammarSync('java.json')
        grammar = registry.grammarForScopeName('source.java')
      })

      it('correctly parses single line comments', () => {
        lines = grammar.tokenizeLines(`\
public void test() {
//comment
}\
`
        )

        const tokens = lines[1]
        assert.deepEqual(tokens[0].scopes, ['source.java', 'comment.line.double-slash.java', 'punctuation.definition.comment.java'])
        assert.equal(tokens[0].value, '//')
        assert.deepEqual(tokens[1].scopes, ['source.java', 'comment.line.double-slash.java'])
        assert.equal(tokens[1].value, 'comment')
      })

      it('correctly parses nested method calls', () => {
        const {line, tags} = grammar.tokenizeLine('a(b(new Object[0]));')
        const tokens = registry.decodeTokens(line, tags)
        const lastToken = tokens[tokens.length - 1]
        assert.deepEqual(lastToken.scopes, ['source.java', 'punctuation.terminator.java'])
        assert.equal(lastToken.value, ';')
      })
    })

    describe('HTML (Ruby - ERB)', () => {
      it('correctly parses strings inside tags', () => {
        grammar = registry.grammarForScopeName('text.html.erb')
        const {line, tags} = grammar.tokenizeLine('<% page_title "My Page" %>')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens[2].value, '"')
        assert.deepEqual(tokens[2].scopes, ['text.html.erb', 'meta.embedded.line.erb', 'source.ruby', 'string.quoted.double.ruby', 'punctuation.definition.string.begin.ruby'])
        assert.equal(tokens[3].value, 'My Page')
        assert.deepEqual(tokens[3].scopes, ['text.html.erb', 'meta.embedded.line.erb', 'source.ruby', 'string.quoted.double.ruby'])
        assert.equal(tokens[4].value, '"')
        assert.deepEqual(tokens[4].scopes, ['text.html.erb', 'meta.embedded.line.erb', 'source.ruby', 'string.quoted.double.ruby', 'punctuation.definition.string.end.ruby'])
      })

      it('does not loop infinitely on <%>', () => {
        loadGrammarSync('html-rails.json')
        loadGrammarSync('ruby-on-rails.json')

        grammar = registry.grammarForScopeName('text.html.erb')
        const {line, tags} = grammar.tokenizeLine('<%>')
        const tokens = registry.decodeTokens(line, tags)

        assert.equal(tokens.length, 1)
        assert.equal(tokens[0].value, '<%>')
        assert.deepEqual(tokens[0].scopes, ['text.html.erb'])
      })
    })

    describe('Unicode support', () => {
      describe('Surrogate pair characters', () =>
        it('correctly parses JavaScript strings containing surrogate pair characters', () => {
          grammar = registry.grammarForScopeName('source.js')
          const {line, tags} = grammar.tokenizeLine("'\uD835\uDF97'")
          const tokens = registry.decodeTokens(line, tags)

          assert.equal(tokens.length, 3)
          assert.equal(tokens[0].value, "'")
          assert.equal(tokens[1].value, '\uD835\uDF97')
          assert.equal(tokens[2].value, "'")
        })
      )

      describe('when the line contains unicode characters', () => {
        it('correctly parses tokens starting after them', () => {
          loadGrammarSync('json.json')
          grammar = registry.grammarForScopeName('source.json')
          const {line, tags} = grammar.tokenizeLine('{"\u2026": 1}')
          const tokens = registry.decodeTokens(line, tags)

          assert.equal(tokens.length, 8)
          assert.equal(tokens[6].value, '1')
          assert.deepEqual(tokens[6].scopes, ['source.json', 'meta.structure.dictionary.json', 'meta.structure.dictionary.value.json', 'constant.numeric.json'])
        })
      })

      describe('when the line contains emoji characters', () => {
        it('correctly terminates quotes & parses tokens starting after them', () => {
          grammar = registry.grammarForScopeName('source.js')

          const withoutEmoji = grammar.tokenizeLine("var emoji = 'xx http://a'; var after;")
          const withoutEmojiTokens = registry.decodeTokens(withoutEmoji.line, withoutEmoji.tags)

          const withEmoji = grammar.tokenizeLine("var emoji = '💻 http://a'; var after;")
          const withEmojiTokens = registry.decodeTokens(withEmoji.line, withEmoji.tags)

          // ignoring this value (the string containing the emoji), they should be identical
          delete withoutEmojiTokens[5].value
          delete withEmojiTokens[5].value

          assert.deepEqual(withEmojiTokens, withoutEmojiTokens)

          assert.equal(withoutEmojiTokens.length, 12)
          assert.equal(withoutEmojiTokens[7].value, ';')
          assert.deepEqual(withoutEmojiTokens[7].scopes, [ 'source.js', 'punctuation.terminator.statement.js' ])

          assert.equal(withEmojiTokens.length, 12)
          assert.equal(withEmojiTokens[7].value, ';')
          assert.deepEqual(withEmojiTokens[7].scopes, [ 'source.js', 'punctuation.terminator.statement.js' ])
        })
      })
    })

    describe('python', () => {
      it('parses import blocks correctly', () => {
        grammar = registry.grammarForScopeName('source.python')
        lines = grammar.tokenizeLines('import a\nimport b')

        const line1 = lines[0]
        assert.equal(line1.length, 3)
        assert.equal(line1[0].value, 'import')
        assert.deepEqual(line1[0].scopes, ['source.python', 'keyword.control.import.python'])
        assert.equal(line1[1].value, ' ')
        assert.deepEqual(line1[1].scopes, ['source.python'])
        assert.equal(line1[2].value, 'a')
        assert.deepEqual(line1[2].scopes, ['source.python'])

        const line2 = lines[1]
        assert.equal(line2.length, 3)
        assert.equal(line2[0].value, 'import')
        assert.deepEqual(line2[0].scopes, ['source.python', 'keyword.control.import.python'])
        assert.equal(line2[1].value, ' ')
        assert.deepEqual(line2[1].scopes, ['source.python'])
        assert.equal(line2[2].value, 'b')
        assert.deepEqual(line2[2].scopes, ['source.python'])
      })

      it('closes all scopes opened when matching rules within a capture', () => {
        grammar = registry.grammarForScopeName('source.python')
        return grammar.tokenizeLines("r'%d(' #foo")
      })
    }) // should not throw exception due to invalid tag sequence

    describe('HTML', () => {
      describe('when it contains CSS', () => {
        it('correctly parses the CSS rules', () => {
          loadGrammarSync('css.json')
          grammar = registry.grammarForScopeName('text.html.basic')

          lines = grammar.tokenizeLines(`\
<html>
  <head>
    <style>
      body {
        color: blue;
      }
    </style>
  </head>
</html>\
`
          )

          const line4 = lines[4]
          assert.equal(line4[4].value, 'blue')
          assert.deepEqual(line4[4].scopes, [
            'text.html.basic',
            'source.css.embedded.html',
            'meta.property-list.css',
            'meta.property-value.css',
            'support.constant.color.w3c-standard-color-name.css'
          ])
        })
      })
    })

    describe('Latex', () => {
      it('properly emits close tags for scope names containing back-references', () => {
        loadGrammarSync('latex.cson')
        grammar = registry.grammarForScopeName('text.tex.latex')
        const {line, tags} = grammar.tokenizeLine('\\chapter*{test}')
        return registry.decodeTokens(line, tags)
      })
    })

    describe('Thrift', () => {
      it("doesn't loop infinitely when the same rule is pushed or popped based on a zero-width match", () => {
        loadGrammarSync('thrift.cson')
        grammar = registry.grammarForScopeName('source.thrift')

        lines = grammar.tokenizeLines(`\
exception SimpleErr {
  1: string message

service SimpleService {
  void Simple() throws (1: SimpleErr simpleErr)
}\
`
        )
      })
    })
  })

  describe("when the position doesn't advance", () => {
    it('logs an error and tokenizes the remainder of the line', () => {
      sandbox.stub(console, 'error')
      loadGrammarSync('loops.json')
      grammar = registry.grammarForScopeName('source.loops')
      const {line, tags, ruleStack} = grammar.tokenizeLine('test')
      const tokens = registry.decodeTokens(line, tags)

      assert.equal(ruleStack.length, 1)
      assert.equal(console.error.callCount, 1)
      assert.equal(tokens.length, 1)
      assert.equal(tokens[0].value, 'test')
      assert.deepEqual(tokens[0].scopes, ['source.loops'])
    })
  })

  describe('when the injection references an included grammar', () => {
    it('adds a pattern for that grammar', () => {
      loadGrammarSync('injection-with-include.cson')
      grammar = registry.grammarForScopeName('test.injections')
      assert.isNotNull(grammar)
      assert.deepEqual(grammar.includedGrammarScopes, ['text.plain'])
    })
  })

  describe('when the grammar is activated/deactivated', () => {
    it('adds/removes it from the registry', () => {
      grammar = new Grammar(registry, {scopeName: 'test-activate'})

      grammar.deactivate()
      assert.equal(registry.grammarForScopeName('test-activate'), undefined)

      grammar.activate()
      assert.equal(registry.grammarForScopeName('test-activate'), grammar)

      grammar.deactivate()
      assert.equal(registry.grammarForScopeName('test-activate'), undefined)
    })
  })
})

path = require 'path'
_ = require 'underscore-plus'
fs = require 'fs-plus'
GrammarRegistry = require '../lib/grammar-registry'
Grammar = require '../lib/grammar'

describe "Grammar tokenization", ->
  [grammar, registry] = []

  loadGrammarSync = (name) ->
    registry.loadGrammarSync(path.join(__dirname, 'fixtures', name))

  beforeEach ->
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

  describe "when the registry is empty", ->
    it "tokenizes using the null grammar", ->
      emptyRegistry = new GrammarRegistry()
      grammar = emptyRegistry.selectGrammar('foo.js', '')
      {line, tags} = grammar.tokenizeLine('a = 1;')
      tokens = emptyRegistry.decodeTokens(line, tags)
      expect(tokens.length).toBe 1
      expect(tokens[0].value).toBe 'a = 1;'
      expect(tokens[0].scopes).toEqual ['text.plain.null-grammar']

    it "allows injections into the null grammar", ->
      registry = new GrammarRegistry()
      loadGrammarSync('hyperlink.json')

      grammar = registry.nullGrammar
      {line, tags} = grammar.tokenizeLine('http://github.com')
      tokens = registry.decodeTokens(line, tags)
      expect(tokens.length).toBe 1
      expect(tokens[0].value).toEqual 'http://github.com'
      expect(tokens[0].scopes).toEqual ['text.plain.null-grammar', 'markup.underline.link.http.hyperlink']

  describe "Registry::loadGrammarSync", ->
    it "returns a grammar for the file path specified", ->
      grammar = loadGrammarSync('hello.cson')
      expect(fs.isFileSync(grammar.path)).toBe true
      expect(grammar).not.toBeNull()

      {line, tags} = grammar.tokenizeLine('hello world!')
      tokens = registry.decodeTokens(line, tags)
      expect(tokens.length).toBe 4

      expect(tokens[0].value).toBe 'hello'
      expect(tokens[0].scopes).toEqual ['source.hello', 'prefix.hello']

      expect(tokens[1].value).toBe ' '
      expect(tokens[1].scopes).toEqual ['source.hello']

      expect(tokens[2].value).toBe 'world'
      expect(tokens[2].scopes).toEqual ['source.hello', 'suffix.hello']

      expect(tokens[3].value).toBe '!'
      expect(tokens[3].scopes).toEqual ['source.hello', 'suffix.hello', 'emphasis.hello']

  describe "::tokenizeLine(line, ruleStack)", ->
    describe "when the entire line matches a single pattern with no capture groups", ->
      it "returns a single token with the correct scope", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine("return")

        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: 'return', scopes: ['source.coffee', 'keyword.control.coffee']}
        ]

    describe "when the entire line matches a single pattern with capture groups", ->
      it "returns a single token with the correct scope", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine("new foo.bar.Baz")
        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: 'new', scopes: ['source.coffee', 'meta.class.instance.constructor', 'keyword.operator.new.coffee']}
          {value: ' ', scopes: ['source.coffee', 'meta.class.instance.constructor']}
          {value: 'foo.bar.Baz', scopes: ['source.coffee', 'meta.class.instance.constructor', 'entity.name.type.instance.coffee']}
        ]

    describe "when the line doesn't match any patterns", ->
      it "returns the entire line as a single simple token with the grammar's scope", ->
        textGrammar = registry.grammarForScopeName('text.plain')
        {line, tags} = textGrammar.tokenizeLine("abc def")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 1

    describe "when the line matches multiple patterns", ->
      it "returns multiple tokens, filling in regions that don't match patterns with tokens in the grammar's global scope", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine(" return new foo.bar.Baz ")

        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: ' ', scopes: ['source.coffee']}
          {value: 'return', scopes: ['source.coffee', 'keyword.control.coffee']}
          {value: ' ', scopes: ['source.coffee']}
          {value: 'new', scopes: ['source.coffee', 'meta.class.instance.constructor', 'keyword.operator.new.coffee']}
          {value: ' ', scopes: ['source.coffee', 'meta.class.instance.constructor']}
          {value: 'foo.bar.Baz', scopes: ['source.coffee', 'meta.class.instance.constructor', 'entity.name.type.instance.coffee']}
          {value: ' ', scopes: ['source.coffee']}
        ]

    describe "when the line matches a pattern with optional capture groups", ->
      it "only returns tokens for capture groups that matched", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine("class Quicksort")
        tokens = registry.decodeTokens(line, tags)

        expect(tokens.length).toBe 3
        expect(tokens[0].value).toBe "class"
        expect(tokens[1].value).toBe " "
        expect(tokens[2].value).toBe "Quicksort"

    describe "when the line matches a rule with nested capture groups and lookahead capture groups beyond the scope of the overall match", ->
      it "creates distinct tokens for nested captures and does not return tokens beyond the scope of the overall capture", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine("  destroy: ->")

        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: '  ', scopes: ["source.coffee"]}
          {value: 'destro', scopes: ["source.coffee", "meta.function.coffee", "entity.name.function.coffee"]}
          # duplicated scope looks wrong, but textmate yields the same behavior. probably a quirk in the coffee grammar.
          {value: 'y', scopes: ["source.coffee", "meta.function.coffee", "entity.name.function.coffee", "entity.name.function.coffee"]}
          {value: ':', scopes: ["source.coffee", "keyword.operator.coffee"]}
          {value: ' ', scopes: ["source.coffee"]}
          {value: '->', scopes: ["source.coffee", "storage.type.function.coffee"]}
        ]

    describe "when the line matches a pattern that includes a rule", ->
      it "returns tokens based on the included rule", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine("7777777")
        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: '7777777', scopes: ['source.coffee', 'constant.numeric.coffee']}
        ]

    describe "when the line is an interpolated string", ->
      it "returns the correct tokens", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine('"the value is #{@x} my friend"')

        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: '"', scopes: ["source.coffee","string.quoted.double.coffee","punctuation.definition.string.begin.coffee"]}
          {value: "the value is ", scopes: ["source.coffee","string.quoted.double.coffee"]}
          {value: '#{', scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","punctuation.section.embedded.coffee"]}
          {value: "@x", scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","variable.other.readwrite.instance.coffee"]}
          {value: "}", scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","punctuation.section.embedded.coffee"]}
          {value: " my friend", scopes: ["source.coffee","string.quoted.double.coffee"]}
          {value: '"', scopes: ["source.coffee","string.quoted.double.coffee","punctuation.definition.string.end.coffee"]}
        ]

    describe "when the line has an interpolated string inside an interpolated string", ->
      it "returns the correct tokens", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine('"#{"#{@x}"}"')

        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: '"',  scopes: ["source.coffee","string.quoted.double.coffee","punctuation.definition.string.begin.coffee"]}
          {value: '#{', scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","punctuation.section.embedded.coffee"]}
          {value: '"',  scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","string.quoted.double.coffee","punctuation.definition.string.begin.coffee"]}
          {value: '#{', scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","string.quoted.double.coffee","source.coffee.embedded.source","punctuation.section.embedded.coffee"]}
          {value: '@x', scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","string.quoted.double.coffee","source.coffee.embedded.source","variable.other.readwrite.instance.coffee"]}
          {value: '}',  scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","string.quoted.double.coffee","source.coffee.embedded.source","punctuation.section.embedded.coffee"]}
          {value: '"',  scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","string.quoted.double.coffee","punctuation.definition.string.end.coffee"]}
          {value: '}',  scopes: ["source.coffee","string.quoted.double.coffee","source.coffee.embedded.source","punctuation.section.embedded.coffee"]}
          {value: '"',  scopes: ["source.coffee","string.quoted.double.coffee","punctuation.definition.string.end.coffee"]}
        ]

    describe "when the line is empty", ->
      it "returns a single token which has the global scope", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine('')
        expect(registry.decodeTokens(line, tags)).toEqual [{value: '',  scopes: ["source.coffee"]}]

    describe "when the line matches no patterns", ->
      it "does not infinitely loop", ->
        grammar = registry.grammarForScopeName('text.plain')
        {line, tags} = grammar.tokenizeLine('hoo')
        expect(registry.decodeTokens(line, tags)).toEqual [{value: 'hoo',  scopes: ["text.plain", "meta.paragraph.text"]}]

    describe "when the line matches a pattern with a 'contentName'", ->
      it "creates tokens using the content of contentName as the token name", ->
        grammar = registry.grammarForScopeName('text.plain')
        {line, tags} = grammar.tokenizeLine('ok, cool')
        expect(registry.decodeTokens(line, tags)).toEqual [{value: 'ok, cool',  scopes: ["text.plain", "meta.paragraph.text"]}]

        grammar = registry.grammarForScopeName('text.plain')
        {line, tags} = grammar.tokenizeLine(' ok, cool')

        expect(registry.decodeTokens(line, tags)).toEqual [
          {value: ' ',  scopes: ["text.plain"]}
          {value: 'ok, cool', scopes: ["text.plain", "meta.paragraph.text"]}
        ]

        loadGrammarSync("content-name.json")

        grammar = registry.grammarForScopeName("source.test")
        lines = grammar.tokenizeLines "#if\ntest\n#endif"

        expect(lines[0].length).toBe 1
        expect(lines[0][0].value).toEqual "#if"
        expect(lines[0][0].scopes).toEqual ["source.test", "pre"]

        expect(lines[1].length).toBe 1
        expect(lines[1][0].value).toEqual "test"
        expect(lines[1][0].scopes).toEqual ["source.test", "pre", "nested"]

        expect(lines[2].length).toBe 2
        expect(lines[2][0].value).toEqual "#endif"
        expect(lines[2][0].scopes).toEqual ["source.test", "pre"]
        expect(lines[2][1].value).toEqual ""
        expect(lines[2][1].scopes).toEqual ["source.test", "all"]

        {line, tags} = grammar.tokenizeLine "test"
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 1
        expect(tokens[0].value).toEqual "test"
        expect(tokens[0].scopes).toEqual ["source.test", "all", "middle"]

        {line, tags} = grammar.tokenizeLine " test"
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 2
        expect(tokens[0].value).toEqual " "
        expect(tokens[0].scopes).toEqual ["source.test", "all"]
        expect(tokens[1].value).toEqual "test"
        expect(tokens[1].scopes).toEqual ["source.test", "all", "middle"]

    describe "when the line matches a pattern with no `name` or `contentName`", ->
      it "creates tokens without adding a new scope", ->
        grammar = registry.grammarForScopeName('source.ruby')
        {line, tags} = grammar.tokenizeLine('%w|oh \\look|')
        tokens = registry.decodeTokens(line, tags)

        expect(tokens.length).toBe 5
        expect(tokens[0]).toEqual value: '%w|', scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby", "punctuation.definition.string.begin.ruby"]
        expect(tokens[1]).toEqual value: 'oh ', scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby"]
        expect(tokens[2]).toEqual value: '\\l', scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby"]
        expect(tokens[3]).toEqual value: 'ook', scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby"]

    describe "when the line matches a begin/end pattern", ->
      it "returns tokens based on the beginCaptures, endCaptures and the child scope", ->
        grammar = registry.grammarForScopeName('source.coffee')
        {line, tags} = grammar.tokenizeLine("'''single-quoted heredoc'''")
        tokens = registry.decodeTokens(line, tags)

        expect(tokens.length).toBe 3

        expect(tokens[0]).toEqual value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.begin.coffee']
        expect(tokens[1]).toEqual value: "single-quoted heredoc", scopes: ['source.coffee', 'string.quoted.heredoc.coffee']
        expect(tokens[2]).toEqual value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.end.coffee']

      describe "when the pattern spans multiple lines", ->
        it "uses the ruleStack returned by the first line to parse the second line", ->
          grammar = registry.grammarForScopeName('source.coffee')
          {line: line1, tags: tags1, ruleStack} = grammar.tokenizeLine("'''single-quoted")
          {line: line2, tags: tags2, ruleStack} = grammar.tokenizeLine("heredoc'''", ruleStack)

          scopes = []
          firstTokens = registry.decodeTokens(line1, tags1, scopes)
          secondTokens = registry.decodeTokens(line2, tags2, scopes)

          expect(firstTokens.length).toBe 2
          expect(secondTokens.length).toBe 2

          expect(firstTokens[0]).toEqual value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.begin.coffee']
          expect(firstTokens[1]).toEqual value: "single-quoted", scopes: ['source.coffee', 'string.quoted.heredoc.coffee']

          expect(secondTokens[0]).toEqual value: "heredoc", scopes: ['source.coffee', 'string.quoted.heredoc.coffee']
          expect(secondTokens[1]).toEqual value: "'''", scopes: ['source.coffee', 'string.quoted.heredoc.coffee', 'punctuation.definition.string.end.coffee']

      describe "when the pattern contains sub-patterns", ->
        it "returns tokens within the begin/end scope based on the sub-patterns", ->
          grammar = registry.grammarForScopeName('source.coffee')
          {line, tags} = grammar.tokenizeLine('"""heredoc with character escape \\t"""')
          tokens = registry.decodeTokens(line, tags)

          expect(tokens.length).toBe 4

          expect(tokens[0]).toEqual value: '"""', scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee', 'punctuation.definition.string.begin.coffee']
          expect(tokens[1]).toEqual value: "heredoc with character escape ", scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee']
          expect(tokens[2]).toEqual value: "\\t", scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee', 'constant.character.escape.coffee']
          expect(tokens[3]).toEqual value: '"""', scopes: ['source.coffee', 'string.quoted.double.heredoc.coffee', 'punctuation.definition.string.end.coffee']

      describe "when applyEndPatternLast flag is set in a pattern", ->
        it "applies end pattern after the other patterns", ->
          grammar = loadGrammarSync('apply-end-pattern-last.cson')
          lines = grammar.tokenizeLines """
            last
            { some }excentricSyntax }

            first
            { some }excentricSyntax }
          """

          expect(lines[1][2]).toEqual value: "}excentricSyntax", scopes: ['source.apply-end-pattern-last', 'end-pattern-last-env', 'scope', 'excentric']
          expect(lines[4][2]).toEqual value: "}", scopes: ['source.apply-end-pattern-last', 'normal-env', 'scope']
          expect(lines[4][3]).toEqual value: "excentricSyntax }", scopes: ['source.apply-end-pattern-last', 'normal-env']

      describe "when the end pattern contains a back reference", ->
        it "constructs the end rule based on its back-references to captures in the begin rule", ->
          grammar = registry.grammarForScopeName('source.ruby')
          {line, tags} = grammar.tokenizeLine('%w|oh|,')
          tokens = registry.decodeTokens(line, tags)

          expect(tokens.length).toBe 4
          expect(tokens[0]).toEqual value: '%w|',  scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby", "punctuation.definition.string.begin.ruby"]
          expect(tokens[1]).toEqual value: 'oh',  scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby"]
          expect(tokens[2]).toEqual value: '|',  scopes: ["source.ruby", "string.quoted.other.literal.lower.ruby", "punctuation.definition.string.end.ruby"]
          expect(tokens[3]).toEqual value: ',',  scopes: ["source.ruby", "punctuation.separator.object.ruby"]

        it "allows the rule containing that end pattern to be pushed to the stack multiple times", ->
          grammar = registry.grammarForScopeName('source.ruby')
          {line, tags} = grammar.tokenizeLine('%Q+matz had some #{%Q-crazy ideas-} for ruby syntax+ # damn.')
          tokens = registry.decodeTokens(line, tags)

          expect(tokens[0]).toEqual value: '%Q+', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","punctuation.definition.string.begin.ruby"]
          expect(tokens[1]).toEqual value: 'matz had some ', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby"]
          expect(tokens[2]).toEqual value: '#{', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","meta.embedded.line.ruby","punctuation.section.embedded.begin.ruby"]
          expect(tokens[3]).toEqual value: '%Q-', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","meta.embedded.line.ruby","source.ruby","string.quoted.other.literal.upper.ruby","punctuation.definition.string.begin.ruby"]
          expect(tokens[4]).toEqual value: 'crazy ideas', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","meta.embedded.line.ruby","source.ruby","string.quoted.other.literal.upper.ruby"]
          expect(tokens[5]).toEqual value: '-', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","meta.embedded.line.ruby","source.ruby","string.quoted.other.literal.upper.ruby","punctuation.definition.string.end.ruby"]
          expect(tokens[6]).toEqual value: '}', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","meta.embedded.line.ruby","punctuation.section.embedded.end.ruby", "source.ruby"]
          expect(tokens[7]).toEqual value: ' for ruby syntax', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby"]
          expect(tokens[8]).toEqual value: '+', scopes: ["source.ruby","string.quoted.other.literal.upper.ruby","punctuation.definition.string.end.ruby"]
          expect(tokens[9]).toEqual value: ' ', scopes: ["source.ruby"]
          expect(tokens[10]).toEqual value: '#', scopes: ["source.ruby","comment.line.number-sign.ruby","punctuation.definition.comment.ruby"]
          expect(tokens[11]).toEqual value: ' damn.', scopes: ["source.ruby","comment.line.number-sign.ruby"]

      describe "when the pattern includes rules from another grammar", ->
        describe "when a grammar matching the desired scope is available", ->
          it "parses tokens inside the begin/end patterns based on the included grammar's rules", ->
            loadGrammarSync('html-rails.json')
            loadGrammarSync('ruby-on-rails.json')

            grammar = registry.grammarForScopeName('text.html.ruby')
            {line, tags} = grammar.tokenizeLine("<div class='name'><%= User.find(2).full_name %></div>")
            tokens = registry.decodeTokens(line, tags)

            expect(tokens[0]).toEqual value: '<', scopes: ["text.html.ruby","meta.tag.block.any.html","punctuation.definition.tag.begin.html"]
            expect(tokens[1]).toEqual value: 'div', scopes: ["text.html.ruby","meta.tag.block.any.html","entity.name.tag.block.any.html"]
            expect(tokens[2]).toEqual value: ' ', scopes: ["text.html.ruby","meta.tag.block.any.html"]
            expect(tokens[3]).toEqual value: 'class', scopes: ["text.html.ruby","meta.tag.block.any.html", "entity.other.attribute-name.html"]
            expect(tokens[4]).toEqual value: '=', scopes: ["text.html.ruby","meta.tag.block.any.html"]
            expect(tokens[5]).toEqual value: '\'', scopes: ["text.html.ruby","meta.tag.block.any.html","string.quoted.single.html","punctuation.definition.string.begin.html"]
            expect(tokens[6]).toEqual value: 'name', scopes: ["text.html.ruby","meta.tag.block.any.html","string.quoted.single.html"]
            expect(tokens[7]).toEqual value: '\'', scopes: ["text.html.ruby","meta.tag.block.any.html","string.quoted.single.html","punctuation.definition.string.end.html"]
            expect(tokens[8]).toEqual value: '>', scopes: ["text.html.ruby","meta.tag.block.any.html","punctuation.definition.tag.end.html"]
            expect(tokens[9]).toEqual value: '<%=', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.section.embedded.ruby"]
            expect(tokens[10]).toEqual value: ' ', scopes: ["text.html.ruby","source.ruby.rails.embedded.html"]
            expect(tokens[11]).toEqual value: 'User', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","support.class.ruby"]
            expect(tokens[12]).toEqual value: '.', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.separator.method.ruby"]
            expect(tokens[13]).toEqual value: 'find', scopes: ["text.html.ruby","source.ruby.rails.embedded.html"]
            expect(tokens[14]).toEqual value: '(', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.section.function.ruby"]
            expect(tokens[15]).toEqual value: '2', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","constant.numeric.ruby"]
            expect(tokens[16]).toEqual value: ')', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.section.function.ruby"]
            expect(tokens[17]).toEqual value: '.', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.separator.method.ruby"]
            expect(tokens[18]).toEqual value: 'full_name ', scopes: ["text.html.ruby","source.ruby.rails.embedded.html"]
            expect(tokens[19]).toEqual value: '%>', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.section.embedded.ruby"]
            expect(tokens[20]).toEqual value: '</', scopes: ["text.html.ruby","meta.tag.block.any.html","punctuation.definition.tag.begin.html"]
            expect(tokens[21]).toEqual value: 'div', scopes: ["text.html.ruby","meta.tag.block.any.html","entity.name.tag.block.any.html"]
            expect(tokens[22]).toEqual value: '>', scopes: ["text.html.ruby","meta.tag.block.any.html","punctuation.definition.tag.end.html"]

          it "updates the grammar if the included grammar is updated later", ->
            loadGrammarSync('html-rails.json')
            loadGrammarSync('ruby-on-rails.json')

            grammar = registry.grammarForScopeName('text.html.ruby')
            grammarUpdatedHandler = jasmine.createSpy("grammarUpdatedHandler")
            grammar.onDidUpdate grammarUpdatedHandler

            {line, tags} = grammar.tokenizeLine("<div class='name'><% <<-SQL select * from users;")
            tokens = registry.decodeTokens(line, tags)
            expect(tokens[12].value).toBe " select * from users;"

            loadGrammarSync('sql.json')
            expect(grammarUpdatedHandler).toHaveBeenCalled()
            {line, tags} = grammar.tokenizeLine("<div class='name'><% <<-SQL select * from users;")
            tokens = registry.decodeTokens(line, tags)
            expect(tokens[12].value).toBe " "
            expect(tokens[13].value).toBe "select"

        describe "when a grammar matching the desired scope is unavailable", ->
          it "updates the grammar if a matching grammar is added later", ->
            registry.removeGrammarForScopeName('text.html.basic')
            loadGrammarSync('html-rails.json')
            loadGrammarSync('ruby-on-rails.json')

            grammar = registry.grammarForScopeName('text.html.ruby')
            {line, tags} = grammar.tokenizeLine("<div class='name'><%= User.find(2).full_name %></div>")
            tokens = registry.decodeTokens(line, tags)
            expect(tokens[0]).toEqual value: "<div class='name'>", scopes: ["text.html.ruby"]
            expect(tokens[1]).toEqual value: '<%=', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.section.embedded.ruby"]
            expect(tokens[2]).toEqual value: ' ', scopes: ["text.html.ruby","source.ruby.rails.embedded.html"]
            expect(tokens[3]).toEqual value: 'User', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","support.class.ruby"]

            loadGrammarSync('html.json')
            {line, tags} = grammar.tokenizeLine("<div class='name'><%= User.find(2).full_name %></div>")
            tokens = registry.decodeTokens(line, tags)
            expect(tokens[0]).toEqual value: '<', scopes: ["text.html.ruby","meta.tag.block.any.html","punctuation.definition.tag.begin.html"]
            expect(tokens[1]).toEqual value: 'div', scopes: ["text.html.ruby","meta.tag.block.any.html","entity.name.tag.block.any.html"]
            expect(tokens[2]).toEqual value: ' ', scopes: ["text.html.ruby","meta.tag.block.any.html"]
            expect(tokens[3]).toEqual value: 'class', scopes: ["text.html.ruby","meta.tag.block.any.html", "entity.other.attribute-name.html"]
            expect(tokens[4]).toEqual value: '=', scopes: ["text.html.ruby","meta.tag.block.any.html"]
            expect(tokens[5]).toEqual value: '\'', scopes: ["text.html.ruby","meta.tag.block.any.html","string.quoted.single.html","punctuation.definition.string.begin.html"]
            expect(tokens[6]).toEqual value: 'name', scopes: ["text.html.ruby","meta.tag.block.any.html","string.quoted.single.html"]
            expect(tokens[7]).toEqual value: '\'', scopes: ["text.html.ruby","meta.tag.block.any.html","string.quoted.single.html","punctuation.definition.string.end.html"]
            expect(tokens[8]).toEqual value: '>', scopes: ["text.html.ruby","meta.tag.block.any.html","punctuation.definition.tag.end.html"]
            expect(tokens[9]).toEqual value: '<%=', scopes: ["text.html.ruby","source.ruby.rails.embedded.html","punctuation.section.embedded.ruby"]
            expect(tokens[10]).toEqual value: ' ', scopes: ["text.html.ruby","source.ruby.rails.embedded.html"]

    it "can parse a grammar with newline characters in its regular expressions (regression)", ->
      grammar = loadGrammarSync('imaginary.cson')
      {line, tags, ruleStack} = grammar.tokenizeLine("// a singleLineComment")
      tokens = registry.decodeTokens(line, tags)
      expect(ruleStack.length).toBe 1
      expect(ruleStack[0].scopeName).toBe "source.imaginaryLanguage"

      expect(tokens.length).toBe 3
      expect(tokens[0].value).toBe "//"
      expect(tokens[1].value).toBe " a singleLineComment"
      expect(tokens[2].value).toBe ""

    it "can parse multiline text using a grammar containing patterns with newlines", ->
      grammar = loadGrammarSync('multiline.cson')
      lines = grammar.tokenizeLines('Xy\\\nzX')

      # Line 0
      expect(lines[0][0]).toEqual
        value: 'X'
        scopes: ['source.multilineLanguage', 'outside-x', 'start']

      expect(lines[0][1]).toEqual
        value: 'y'
        scopes: ['source.multilineLanguage', 'outside-x']

      expect(lines[0][2]).toEqual
        value: '\\'
        scopes: ['source.multilineLanguage', 'outside-x', 'inside-x']

      expect(lines[0][3]).not.toBeDefined()

      # Line 1
      expect(lines[1][0]).toEqual
        value: 'z'
        scopes: ['source.multilineLanguage', 'outside-x']

      expect(lines[1][1]).toEqual
        value: 'X'
        scopes: ['source.multilineLanguage', 'outside-x', 'end']

      expect(lines[1][2]).not.toBeDefined()

    it "does not loop infinitely (regression)", ->
      grammar = registry.grammarForScopeName('source.js')
      {line, tags, ruleStack} = grammar.tokenizeLine("// line comment")
      {line, tags, ruleStack} = grammar.tokenizeLine(" // second line comment with a single leading space", ruleStack)

    describe "when inside a C block", ->
      beforeEach ->
        loadGrammarSync('c.json')
        loadGrammarSync('c-plus-plus.json')
        grammar = registry.grammarForScopeName('source.c')

      it "correctly parses a method. (regression)", ->
        {line, tags, ruleStack} = grammar.tokenizeLine("if(1){m()}")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens[5]).toEqual value: "m", scopes: ["source.c", "meta.block.c", "meta.function-call.c", "support.function.any-method.c"]

      it "correctly parses nested blocks. (regression)", ->
        {line, tags, ruleStack} = grammar.tokenizeLine("if(1){if(1){m()}}")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens[5]).toEqual value: "if", scopes: ["source.c", "meta.block.c", "keyword.control.c"]
        expect(tokens[10]).toEqual value: "m", scopes: ["source.c", "meta.block.c", "meta.block.c", "meta.function-call.c", "support.function.any-method.c"]

    describe "when the grammar can infinitely loop over a line", ->
      it "aborts tokenization", ->
        spyOn(console, 'error')
        grammar = loadGrammarSync('infinite-loop.cson')
        {line, tags} = grammar.tokenizeLine("abc")
        scopes = []
        tokens = registry.decodeTokens(line, tags, scopes)
        expect(tokens[0].value).toBe "a"
        expect(tokens[1].value).toBe "bc"
        expect(scopes).toEqual [registry.startIdForScope(grammar.scopeName)]
        expect(console.error).toHaveBeenCalled()

    describe "when a grammar has a pattern that has back references in the match value", ->
      it "does not special handle the back references and instead allows oniguruma to resolve them", ->
        loadGrammarSync('scss.json')
        grammar = registry.grammarForScopeName('source.css.scss')
        {line, tags} = grammar.tokenizeLine("@mixin x() { -moz-selector: whatever; }")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens[9]).toEqual value: "-moz-selector", scopes: ["source.css.scss", "meta.property-list.scss", "meta.property-name.scss"]

    describe "when a line has more tokens than `maxTokensPerLine`", ->
      it "creates a final token with the remaining text and resets the ruleStack to match the begining of the line", ->
        grammar = registry.grammarForScopeName('source.js')
        originalRuleStack = grammar.tokenizeLine('').ruleStack
        spyOn(grammar, 'getMaxTokensPerLine').andCallFake -> 5
        {line, tags, ruleStack} = grammar.tokenizeLine("var x = /[a-z]/;", originalRuleStack)
        scopes = []
        tokens = registry.decodeTokens(line, tags, scopes)
        expect(tokens.length).toBe 6
        expect(tokens[5].value).toBe "[a-z]/;"
        expect(ruleStack).toEqual originalRuleStack
        expect(ruleStack).not.toBe originalRuleStack
        expect(scopes.length).toBe 0

    describe "when a grammar has a capture with patterns", ->
      it "matches the patterns and includes the scope specified as the pattern's match name", ->
        grammar = registry.grammarForScopeName('text.html.php')
        {line, tags} = grammar.tokenizeLine("<?php public final function meth() {} ?>")
        tokens = registry.decodeTokens(line, tags)

        expect(tokens[2].value).toBe "public"
        expect(tokens[2].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php", "storage.modifier.php"]

        expect(tokens[3].value).toBe " "
        expect(tokens[3].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php"]

        expect(tokens[4].value).toBe "final"
        expect(tokens[4].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php", "storage.modifier.php"]

        expect(tokens[5].value).toBe " "
        expect(tokens[5].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php"]

        expect(tokens[6].value).toBe "function"
        expect(tokens[6].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php", "storage.type.function.php"]

      it "ignores child captures of a capture with patterns", ->
        grammar = loadGrammarSync('nested-captures.cson')
        {line, tags} = grammar.tokenizeLine("ab")
        tokens = registry.decodeTokens(line, tags)

        expect(tokens[0].value).toBe "ab"
        expect(tokens[0].scopes).toEqual ["nested", "text", "a"]

    describe "when the grammar has injections", ->
      it "correctly includes the injected patterns when tokenizing", ->
        grammar = registry.grammarForScopeName('text.html.php')
        {line, tags} = grammar.tokenizeLine("<div><?php function hello() {} ?></div>")
        tokens = registry.decodeTokens(line, tags)

        expect(tokens[3].value).toBe "<?php"
        expect(tokens[3].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "punctuation.section.embedded.begin.php"]

        expect(tokens[5].value).toBe "function"
        expect(tokens[5].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php", "storage.type.function.php"]

        expect(tokens[7].value).toBe "hello"
        expect(tokens[7].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "source.php", "meta.function.php", "entity.name.function.php"]

        expect(tokens[14].value).toBe "?"
        expect(tokens[14].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "punctuation.section.embedded.end.php", "source.php"]

        expect(tokens[15].value).toBe ">"
        expect(tokens[15].scopes).toEqual ["text.html.php", "meta.embedded.line.php", "punctuation.section.embedded.end.php"]

        expect(tokens[16].value).toBe "</"
        expect(tokens[16].scopes).toEqual ["text.html.php", "meta.tag.block.any.html", "punctuation.definition.tag.begin.html"]

        expect(tokens[17].value).toBe "div"
        expect(tokens[17].scopes).toEqual ["text.html.php", "meta.tag.block.any.html", "entity.name.tag.block.any.html"]

    describe "when the grammar's pattern name has a group number in it", ->
      it "replaces the group number with the matched captured text", ->
        grammar = loadGrammarSync('hyperlink.json')
        {line, tags} = grammar.tokenizeLine("https://github.com")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens[0].scopes).toEqual ["text.hyperlink", "markup.underline.link.https.hyperlink"]

    describe "when the grammar has an injection selector", ->
      it "includes the grammar's patterns when the selector matches the current scope in other grammars", ->
        loadGrammarSync('hyperlink.json')
        grammar = registry.grammarForScopeName("source.js")
        {line, tags} = grammar.tokenizeLine("var i; // http://github.com")
        tokens = registry.decodeTokens(line, tags)

        expect(tokens[0].value).toBe "var"
        expect(tokens[0].scopes).toEqual ["source.js", "storage.modifier.js"]

        expect(tokens[6].value).toBe "http://github.com"
        expect(tokens[6].scopes).toEqual ["source.js", "comment.line.double-slash.js", "markup.underline.link.http.hyperlink"]

    describe "when the position doesn't advance and rule includes $self and matches itself", ->
      it "tokenizes the entire line using the rule", ->
        grammar = loadGrammarSync('forever.cson')
        {line, tags} = grammar.tokenizeLine("forever and ever")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 1
        expect(tokens[0].value).toBe "forever and ever"
        expect(tokens[0].scopes).toEqual ["source.forever", "text"]

    describe "${capture:/command} style pattern names", ->
      it "replaces the number with the capture group and translates the text", ->
        loadGrammarSync('todo.json')
        grammar = registry.grammarForScopeName('source.ruby')
        {line, tags} = grammar.tokenizeLine "# TODO be nicer"
        tokens = registry.decodeTokens(line, tags)

        expect(tokens[2].value).toEqual "TODO"
        expect(tokens[2].scopes).toEqual ["source.ruby", "comment.line.number-sign.ruby", "storage.type.class.todo"]

    describe "$number style pattern names", ->
      it "replaces the number with the capture group and translates the text", ->
        loadGrammarSync('makefile.json')
        grammar = registry.grammarForScopeName('source.makefile')
        {line, tags} = grammar.tokenizeLine("ifeq")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 1
        expect(tokens[0].value).toEqual "ifeq"
        expect(tokens[0].scopes).toEqual ["source.makefile", "meta.scope.conditional.makefile", "keyword.control.ifeq.makefile"]

        {line, tags} = grammar.tokenizeLine("ifeq (")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 2
        expect(tokens[0].value).toEqual "ifeq"
        expect(tokens[0].scopes).toEqual ["source.makefile", "meta.scope.conditional.makefile", "keyword.control.ifeq.makefile"]
        expect(tokens[1].value).toEqual " ("
        expect(tokens[1].scopes).toEqual ["source.makefile", "meta.scope.conditional.makefile", "meta.scope.condition.makefile"]

      it "removes leading dot characters from the replaced capture index placeholder", ->
        loadGrammarSync('makefile.json')
        grammar = registry.grammarForScopeName('source.makefile')
        {line, tags}  = grammar.tokenizeLine(".PHONY:")
        tokens = registry.decodeTokens(line, tags)
        expect(tokens.length).toBe 2
        expect(tokens[0].scopes).toEqual ["source.makefile", "meta.scope.target.makefile", "support.function.target.PHONY.makefile"]
        expect(tokens[0].value).toEqual ".PHONY"

  describe "language-specific integration tests", ->
    lines = null

    describe "Git commit messages", ->
      beforeEach ->
        grammar = loadGrammarSync('git-commit.json')
        lines = grammar.tokenizeLines """
          longggggggggggggggggggggggggggggggggggggggggggggggg
          # Please enter the commit message for your changes. Lines starting
        """

      it "correctly parses a long line", ->
        tokens = lines[0]
        expect(tokens[0].value).toBe "longggggggggggggggggggggggggggggggggggggggggggggggg"
        expect(tokens[0].scopes).toEqual ["text.git-commit", "meta.scope.message.git-commit", "invalid.deprecated.line-too-long.git-commit"]

      it "correctly parses the number sign of the first comment line", ->
        tokens = lines[1]
        expect(tokens[0].value).toBe "#"
        expect(tokens[0].scopes).toEqual ["text.git-commit", "meta.scope.metadata.git-commit", "comment.line.number-sign.git-commit", "punctuation.definition.comment.git-commit"]

    describe "C++", ->
      beforeEach ->
        loadGrammarSync('c.json')
        grammar = loadGrammarSync('c-plus-plus.json')
        lines = grammar.tokenizeLines """
          #include "a.h"
          #include "b.h"
        """

      it "correctly parses the first include line", ->
        tokens = lines[0]
        expect(tokens[0].value).toBe "#"
        expect(tokens[0].scopes).toEqual ["source.c++", "meta.preprocessor.c.include"]
        expect(tokens[1].value).toBe 'include'
        expect(tokens[1].scopes).toEqual ["source.c++", "meta.preprocessor.c.include", "keyword.control.import.include.c"]

      it "correctly parses the second include line", ->
        tokens = lines[1]
        expect(tokens[0].value).toBe "#"
        expect(tokens[0].scopes).toEqual ["source.c++", "meta.preprocessor.c.include"]
        expect(tokens[1].value).toBe 'include'
        expect(tokens[1].scopes).toEqual ["source.c++", "meta.preprocessor.c.include", "keyword.control.import.include.c"]

    describe "Ruby", ->
      beforeEach ->
        grammar = registry.grammarForScopeName('source.ruby')
        lines = grammar.tokenizeLines """
          a = {
            "b" => "c",
          }
        """

      it "doesn't loop infinitely (regression)", ->
        expect(_.pluck(lines[0], 'value').join('')).toBe 'a = {'
        expect(_.pluck(lines[1], 'value').join('')).toBe '  "b" => "c",'
        expect(_.pluck(lines[2], 'value').join('')).toBe '}'
        expect(_.pluck(lines[3], 'value').join('')).toBe ''

    describe "Objective-C", ->
      beforeEach ->
        loadGrammarSync('c.json')
        loadGrammarSync('c-plus-plus.json')
        loadGrammarSync('objective-c.json')
        grammar = loadGrammarSync('objective-c-plus-plus.json')
        lines = grammar.tokenizeLines """
          void test() {
          NSString *a = @"a\\nb";
          }
        """

      it "correctly parses variable type when it is a built-in Cocoa class", ->
        tokens = lines[1]
        expect(tokens[0].value).toBe "NSString"
        expect(tokens[0].scopes).toEqual ["source.objc++", "meta.function.c", "meta.block.c", "support.class.cocoa"]

      it "correctly parses the semicolon at the end of the line", ->
        tokens = lines[1]
        lastToken = _.last(tokens)
        expect(lastToken.value).toBe ";"
        expect(lastToken.scopes).toEqual ["source.objc++", "meta.function.c", "meta.block.c"]

      it "correctly parses the string characters before the escaped character", ->
        tokens = lines[1]
        expect(tokens[2].value).toBe '@"'
        expect(tokens[2].scopes).toEqual ["source.objc++", "meta.function.c", "meta.block.c", "string.quoted.double.objc", "punctuation.definition.string.begin.objc"]

    describe "Java", ->
      beforeEach ->
        loadGrammarSync('java.json')
        grammar = registry.grammarForScopeName('source.java')

      it "correctly parses single line comments", ->
        lines = grammar.tokenizeLines """
          public void test() {
          //comment
          }
        """

        tokens = lines[1]
        expect(tokens[0].scopes).toEqual ["source.java", "comment.line.double-slash.java", "punctuation.definition.comment.java"]
        expect(tokens[0].value).toEqual '//'
        expect(tokens[1].scopes).toEqual ["source.java", "comment.line.double-slash.java"]
        expect(tokens[1].value).toEqual 'comment'

      it "correctly parses nested method calls", ->
        {line, tags} = grammar.tokenizeLine('a(b(new Object[0]));')
        tokens = registry.decodeTokens(line, tags)
        lastToken = _.last(tokens)
        expect(lastToken.scopes).toEqual ['source.java', 'punctuation.terminator.java']
        expect(lastToken.value).toEqual ';'

    describe "HTML (Ruby - ERB)", ->
      it "correctly parses strings inside tags", ->
        grammar = registry.grammarForScopeName('text.html.erb')
        {line, tags} = grammar.tokenizeLine '<% page_title "My Page" %>'
        tokens = registry.decodeTokens(line, tags)

        expect(tokens[2].value).toEqual '"'
        expect(tokens[2].scopes).toEqual ["text.html.erb", "meta.embedded.line.erb", "source.ruby", "string.quoted.double.ruby", "punctuation.definition.string.begin.ruby"]
        expect(tokens[3].value).toEqual 'My Page'
        expect(tokens[3].scopes).toEqual ["text.html.erb", "meta.embedded.line.erb", "source.ruby", "string.quoted.double.ruby"]
        expect(tokens[4].value).toEqual '"'
        expect(tokens[4].scopes).toEqual ["text.html.erb", "meta.embedded.line.erb", "source.ruby", "string.quoted.double.ruby", "punctuation.definition.string.end.ruby"]

      it "does not loop infinitely on <%>", ->
        loadGrammarSync('html-rails.json')
        loadGrammarSync('ruby-on-rails.json')

        grammar = registry.grammarForScopeName('text.html.erb')
        {line, tags} = grammar.tokenizeLine('<%>')
        tokens = registry.decodeTokens(line, tags)

        expect(tokens.length).toBe 1
        expect(tokens[0].value).toEqual '<%>'
        expect(tokens[0].scopes).toEqual ["text.html.erb"]

    describe "Unicode support", ->
      describe "Surrogate pair characters", ->
        it "correctly parses JavaScript strings containing surrogate pair characters", ->
          grammar = registry.grammarForScopeName('source.js')
          {line, tags} = grammar.tokenizeLine "'\uD835\uDF97'"
          tokens = registry.decodeTokens(line, tags)

          expect(tokens.length).toBe 3
          expect(tokens[0].value).toBe "'"
          expect(tokens[1].value).toBe "\uD835\uDF97"
          expect(tokens[2].value).toBe "'"

      describe "when the line contains unicode characters", ->
        it "correctly parses tokens starting after them", ->
          loadGrammarSync('json.json')
          grammar = registry.grammarForScopeName('source.json')
          {line, tags} = grammar.tokenizeLine '{"\u2026": 1}'
          tokens = registry.decodeTokens(line, tags)

          expect(tokens.length).toBe 8
          expect(tokens[6].value).toBe '1'
          expect(tokens[6].scopes).toEqual ["source.json", "meta.structure.dictionary.json", "meta.structure.dictionary.value.json", "constant.numeric.json"]

    describe "python", ->
      it "parses import blocks correctly", ->
        grammar = registry.grammarForScopeName('source.python')
        lines = grammar.tokenizeLines "import a\nimport b"

        line1 = lines[0]
        expect(line1.length).toBe 3
        expect(line1[0].value).toEqual "import"
        expect(line1[0].scopes).toEqual ["source.python", "keyword.control.import.python"]
        expect(line1[1].value).toEqual " "
        expect(line1[1].scopes).toEqual ["source.python"]
        expect(line1[2].value).toEqual "a"
        expect(line1[2].scopes).toEqual ["source.python"]

        line2 = lines[1]
        expect(line2.length).toBe 3
        expect(line2[0].value).toEqual "import"
        expect(line2[0].scopes).toEqual ["source.python", "keyword.control.import.python"]
        expect(line2[1].value).toEqual " "
        expect(line2[1].scopes).toEqual ["source.python"]
        expect(line2[2].value).toEqual "b"
        expect(line2[2].scopes).toEqual ["source.python"]

      it "closes all scopes opened when matching rules within a capture", ->
        grammar = registry.grammarForScopeName('source.python')
        grammar.tokenizeLines("r'%d(' #foo") # should not throw exception due to invalid tag sequence

    describe "HTML", ->
      describe "when it contains CSS", ->
        it "correctly parses the CSS rules", ->
          loadGrammarSync("css.json")
          grammar = registry.grammarForScopeName("text.html.basic")

          lines = grammar.tokenizeLines """
            <html>
              <head>
                <style>
                  body {
                    color: blue;
                  }
                </style>
              </head>
            </html>
          """

          line4 = lines[4]
          expect(line4[4].value).toEqual "blue"
          expect(line4[4].scopes).toEqual [
            "text.html.basic"
            "source.css.embedded.html"
            "meta.property-list.css"
            "meta.property-value.css"
            "support.constant.color.w3c-standard-color-name.css"
          ]

    describe "Latex", ->
      it "properly emits close tags for scope names containing back-references", ->
        loadGrammarSync("latex.cson")
        grammar = registry.grammarForScopeName("text.tex.latex")
        {line, tags} = grammar.tokenizeLine("\\chapter*{test}")
        registry.decodeTokens(line, tags)

    describe "Thrift", ->
      it "doesn't loop on this evil example", ->
        loadGrammarSync("thrift.cson")
        grammar = registry.grammarForScopeName("source.thrift")

        lines = grammar.tokenizeLines """
          exception SimpleErr {
            1: string message

          service SimpleService {
            void Simple() throws (1: SimpleErr simpleErr)
          }
        """

  describe "when the position doesn't advance", ->
    it "logs an error and tokenizes the remainder of the line", ->
      spyOn(console, 'error')
      loadGrammarSync("loops.json")
      grammar = registry.grammarForScopeName("source.loops")
      {line, tags, ruleStack} = grammar.tokenizeLine('test')
      tokens = registry.decodeTokens(line, tags)

      expect(ruleStack.length).toBe 1
      expect(console.error.callCount).toBe 1
      expect(tokens.length).toBe 1
      expect(tokens[0].value).toEqual 'test'
      expect(tokens[0].scopes).toEqual ['source.loops']

  describe "when the injection references an included grammar", ->
    it "adds a pattern for that grammar", ->
      loadGrammarSync("injection-with-include.cson")
      grammar = registry.grammarForScopeName("test.injections")
      expect(grammar).not.toBeNull()
      expect(grammar.includedGrammarScopes).toEqual ['text.plain']

  describe "when the grammar is activated/deactivated", ->
    it "adds/removes it from the registry", ->
      grammar = new Grammar(registry, {scopeName: 'test-activate'})

      grammar.deactivate()
      expect(registry.grammarForScopeName('test-activate')).toBeUndefined()

      grammar.activate()
      expect(registry.grammarForScopeName('test-activate')).toBe grammar

      grammar.deactivate()
      expect(registry.grammarForScopeName('test-activate')).toBeUndefined()

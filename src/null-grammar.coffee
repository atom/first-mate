{Emitter} = require 'emissary'

module.exports =
class NullGrammar
  Emitter.includeInto(this)

  name: 'Null Grammar'
  scopeName: 'text.plain.null-grammar'

  getScore: -> 0

  tokenizeLine: (line) ->
    tokens: [{value: line, scopes: ['null-grammar.text.plain']}]

  tokenizeLines: (text) ->
    lines = text.split('\n')
    for line in lines
      {tokens} = @tokenizeLine(line)
      tokens

  grammarUpdated: -> # noop

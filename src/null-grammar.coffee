Grammar = require './grammar'

# A grammar with no patterns that is always available from a {GrammarRegistry}
module.exports =
class NullGrammar extends Grammar
  constructor: (registry) ->
    name = 'Null Grammar'
    scopeName = 'text.plain.null-grammar'
    super(registry, {name, scopeName})

  getScore: -> 0

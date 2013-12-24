# First Mate [![Build Status](https://travis-ci.org/atom/first-mate.png)](https://travis-ci.org/atom/first-mate)

TextMate helpers

## Installing

```sh
npm install first-mate
```

## Using

### ScopeSelector

```coffeescript
{ScopeSelector} = require 'first-mate'
selector = new ScopeSelector('a | b')
selector.matches(['c']) # false
selector.matches(['a']) # true
```

### GrammarRegistry

```coffeescript
{GrammarRegistry} = require 'first-mate'
registry = new GrammarRegistry()
grammar = registry.loadGrammarSync('./spec/fixtures/javascript.json')
{tokens} = grammar.tokenizeLine('var offset = 3;')
for {value, scopes} in tokens
  console.log("Token text: '#{value}' with scopes: #{scopes}")
```

## Developing

  * Clone the repository
  * Run `npm install`
  * Run `npm test` to run the specs
  * Run `npm run benchmark` to benchmark fully tokenizing jQuery 2.0.3

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

#### loadGrammar(grammarPath, callback)

Asynchronously load a grammar and add it to the registry.

`grammarPath` - A string path to the grammar file.

`callback` - A function to call after the grammar is read and added to the
registry.  The callback receives `(error, grammar)` arguments.

#### loadGrammarSync(grammarPath)

Synchronously load a grammar and add it to the registry.

`grammarPath` - A string path to the grammar file.

Returns a `Grammar` instance.

## Developing

  * Clone the repository
  * Run `npm install`
  * Run `npm test` to run the specs
  * Run `npm run benchmark` to benchmark fully tokenizing jQuery 2.0.3

# First Mate [![Build Status](https://travis-ci.org/atom/first-mate.svg?branch=master)](https://travis-ci.org/atom/first-mate)

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

### Grammar

#### setConfigFileTypes([configFileTypes])

Sets the list of user-configured file types for this grammar.

`configFileTypes` - An array of file types to be matched against.

#### tokenizeLine(line, [ruleStack], [firstLine])

Generate the tokenize for the given line of text.

`line` - The string text of the line.

`ruleStack` - An array of Rule objects that was returned from a previous call
to this method.

`firstLine` - `true` to indicate that the very first line is being tokenized.

Returns an object with a `tokens` key pointing to an array of token objects
and a `ruleStack` key pointing to an array of rules to pass to this method
on future calls for lines proceeding the line that was just tokenized.

#### tokenizeLines(text)

`text` - The string text possibly containing newlines.

Returns an array of tokens for each line tokenized.

## Developing

  * Clone the repository
  * Run `npm install`
  * Run `npm test` to run the specs
  * Run `npm run benchmark` to benchmark fully tokenizing jQuery 2.0.3 and
    the CSS for Twitter Bootstrap 3.1.1

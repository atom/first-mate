# First Mate [![Build Status](https://travis-ci.org/atom/first-mate.png)](https://travis-ci.org/atom/first-mate)

TextMate helpers

## Installing

```sh
npm install first-mate
```

## Using

```coffeescript
{ScopeSelector} = require 'first-mate'
selector = new ScopeSelector('a | b')
selector.matches(['c']) # false
selector.matches(['a']) # true
```

## Developing

  * Clone the repository
  * Run `npm install`
  * Run `npm test` to run the specs
  * Run `npm run benchmark` to benchmark fully tokenizing jQuery 2.0.3

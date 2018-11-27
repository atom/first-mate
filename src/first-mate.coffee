module.exports =
  ScopeSelector: require './scope-selector'
  GrammarRegistry: require './grammar-registry'
  Grammar: require './grammar'

# This allows this file to be processed with `electron-link`
Object.defineProperty(module.exports, 'OnigRegExp', {
  get: -> require('oniguruma').OnigRegExp
})

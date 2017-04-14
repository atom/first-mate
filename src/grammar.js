import _ from 'underscore-plus'
import {OnigRegExp} from 'oniguruma'
import {Emitter} from 'event-kit'

import Injections from './injections'
import Pattern from './pattern'
import Rule from './rule'
import ScopeSelector from './scope-selector'

// Extended: Grammar that tokenizes lines of text.
//
// This class should not be instantiated directly but instead obtained from
// a {GrammarRegistry} by calling {GrammarRegistry::loadGrammar}.
export default class Grammar {
  constructor (registry, options = {}) {
    this.registration = null
    this.registry = registry;
    ({name: this.name, fileTypes: this.fileTypes, scopeName: this.scopeName, foldingStopMarker: this.foldingStopMarker, maxTokensPerLine: this.maxTokensPerLine, maxLineLength: this.maxLineLength} = options)
    const {injections, injectionSelector, patterns, repository, firstLineMatch} = options

    this.emitter = new Emitter()
    this.repository = null
    this.initialRule = null

    this.rawPatterns = patterns
    this.rawRepository = repository

    if (injectionSelector) {
      this.injectionSelector = new ScopeSelector(injectionSelector)
    } else {
      this.injectionSelector = null
    }

    if (firstLineMatch) {
      this.firstLineRegex = new OnigRegExp(firstLineMatch)
    } else {
      this.firstLineRegex = null
    }

    if (!this.fileTypes) { this.fileTypes = [] }
    this.includedGrammarScopes = []

    // Create last since Injections uses APIs from this class
    this.injections = new Injections(this, injections)
  }

  /*
  Section: Event Subscription
  */

  // Public: Invoke the given callback when this grammar is updated due to a
  // grammar it depends on being added or removed from the registry.
  //
  // * `callback` {Function} to call when this grammar is updated.
  //
  // Returns a {Disposable} on which `.dispose()` can be called to unsubscribe.
  onDidUpdate (callback) {
    return this.emitter.on('did-update', callback)
  }

  /*
  Section: Tokenizing
  */

  // Public: Tokenize all lines in the given text.
  //
  // * `text` A {String} containing one or more lines.
  //
  // Returns an {Array} of token arrays for each line tokenized.
  tokenizeLines (text) {
    const lines = text.split('\n')
    let tags, ruleStack

    const scopes = []
    return lines.map((line, lineNumber) => {
      ({tags, ruleStack} = this.tokenizeLine(line, ruleStack, lineNumber === 0))
      return this.registry.decodeTokens(line, tags, scopes)
    })
  }

  // Public: Tokenize the line of text.
  //
  // * `line` A {String} of text to tokenize.
  // * `ruleStack` An optional {Array} of rules previously returned from this
  //   method. This should be null when tokenizing the first line in the file.
  // * `firstLine` A optional {Boolean} denoting whether this is the first line
  //   in the file which defaults to `false`. This should be `true`
  //   when tokenizing the first line in the file.
  //
  // Returns an {Object} containing the following properties:
  // * `line` The {String} of text that was tokenized.
  // * `tags` An {Array} of integer scope ids and strings. Positive ids
  //   indicate the beginning of a scope, and negative tags indicate the end.
  //   To resolve ids to scope names, call {GrammarRegistry::scopeForId} with the
  //   absolute value of the id.
  // * `tokens` This is a dynamic property. Invoking it will incur additional
  //   overhead, but will automatically translate the `tags` into token objects
  //   with `value` and `scopes` properties.
  // * `ruleStack` An {Array} of rules representing the tokenized state at the
  //   end of the line. These should be passed back into this method when
  //   tokenizing the next line in the file.
  tokenizeLine (inputLine, ruleStack, firstLine = false, compatibilityMode = true) {
    let line, openScopeTags
    const tags = []

    let truncatedLine = false
    if (inputLine.length > this.maxLineLength) {
      line = inputLine.slice(0, this.maxLineLength)
      truncatedLine = true
    } else {
      line = inputLine
    }

    if (ruleStack) {
      ruleStack = ruleStack.slice()
      if (compatibilityMode) {
        openScopeTags = []
        for (let {scopeName, contentScopeName} of ruleStack) {
          if (scopeName) { openScopeTags.push(this.registry.startIdForScope(scopeName)) }
          if (contentScopeName) { openScopeTags.push(this.registry.startIdForScope(contentScopeName)) }
        }
      }
    } else {
      if (compatibilityMode) { openScopeTags = [] }
      const initialRule = this.getInitialRule()
      let {scopeName, contentScopeName} = initialRule
      ruleStack = [{rule: initialRule, scopeName, contentScopeName}]
      if (scopeName) { tags.push(this.startIdForScope(initialRule.scopeName)) }
      if (contentScopeName) { tags.push(this.startIdForScope(initialRule.contentScopeName)) }
    }

    const initialRuleStackLength = ruleStack.length
    let position = 0
    let tokenCount = 0

    while (true) {
      const previousRuleStackLength = ruleStack.length
      const previousPosition = position

      if (position === line.length + 1) { break } // include trailing newline position

      if (tokenCount >= this.getMaxTokensPerLine() - 1) {
        truncatedLine = true
        break
      }

      const match = _.last(ruleStack).rule.getNextTags(ruleStack, line, position, firstLine)
      if (match) {
        const {nextTags, tagsStart, tagsEnd} = match

        // Unmatched text before next tags
        if (position < tagsStart) {
          tags.push(tagsStart - position)
          tokenCount++
        }

        tags.push(...nextTags)
        for (let tag of nextTags) { if (tag >= 0) { tokenCount++ } }
        position = tagsEnd
      } else {
        // Push filler token for unmatched text at end of line
        if (position < line.length || line.length === 0) {
          tags.push(line.length - position)
        }
        break
      }

      if (position === previousPosition) {
        if (ruleStack.length === previousRuleStackLength) {
          console.error(`Popping rule because it loops at column ${position} of line '${line}'`, _.clone(ruleStack))
          if (ruleStack.length > 1) {
            let {scopeName, contentScopeName} = ruleStack.pop()
            if (contentScopeName) { tags.push(this.endIdForScope(contentScopeName)) }
            if (scopeName) { tags.push(this.endIdForScope(scopeName)) }
          } else {
            if (position < line.length || (line.length === 0 && tags.length === 0)) {
              tags.push(line.length - position)
            }
            break
          }
        } else if (ruleStack.length > previousRuleStackLength) { // Stack size increased with zero length match
          let popStack
          const [{rule: penultimateRule}, {rule: lastRule}] = ruleStack.slice(-2)

          // Same exact rule was pushed but position wasn't advanced
          if (lastRule && lastRule === penultimateRule) {
            popStack = true
          }

          // Rule with same scope name as previous rule was pushed but position wasn't advanced
          if (lastRule && lastRule.scopeName && penultimateRule.scopeName === lastRule.scopeName) {
            popStack = true
          }

          if (popStack) {
            ruleStack.pop()
            const lastSymbol = _.last(tags)
            if (lastSymbol < 0 && lastSymbol === this.startIdForScope(lastRule.scopeName)) {
              tags.pop() // also pop the duplicated start scope if it was pushed
            }
            tags.push(line.length - position)
            break
          }
        }
      }
    }

    if (truncatedLine) {
      const tagCount = tags.length
      if (tags[tagCount - 1] > 0) {
        tags[tagCount - 1] += inputLine.length - position
      } else {
        tags.push(inputLine.length - position)
      }
      while (ruleStack.length > initialRuleStackLength) {
        let {scopeName, contentScopeName} = ruleStack.pop()
        if (contentScopeName) { tags.push(this.endIdForScope(contentScopeName)) }
        if (scopeName) { tags.push(this.endIdForScope(scopeName)) }
      }
    }

    for (let {rule} of ruleStack) { rule.clearAnchorPosition() }

    if (compatibilityMode) {
      return new TokenizeLineResult(inputLine, openScopeTags, tags, ruleStack, this.registry)
    } else {
      return {line: inputLine, tags, ruleStack}
    }
  }

  activate () {
    this.registration = this.registry.addGrammar(this)
  }

  deactivate () {
    this.emitter = new Emitter()
    if (this.registration) {
      this.registration.dispose()
    }
    this.registration = null
  }

  clearRules () {
    this.initialRule = null
    this.repository = null
  }

  getInitialRule () {
    return this.initialRule ? this.initialRule : (this.initialRule = this.createRule({scopeName: this.scopeName, patterns: this.rawPatterns}))
  }

  getRepository () {
    return this.repository ? this.repository : (this.repository = (() => {
      const repository = {}
      for (let name in this.rawRepository) {
        let data = this.rawRepository[name]
        if (data.begin || data.match) { data = {patterns: [data], tempName: name} }
        repository[name] = this.createRule(data)
      }
      return repository
    })())
  }

  addIncludedGrammarScope (scope) {
    if (!_.include(this.includedGrammarScopes, scope)) { return this.includedGrammarScopes.push(scope) }
  }

  grammarUpdated (scopeName) {
    if (!_.include(this.includedGrammarScopes, scopeName)) { return false }
    this.clearRules()
    this.registry.grammarUpdated(this.scopeName)
    this.emitter.emit('did-update')
    return true
  }

  startIdForScope (scope) { return this.registry.startIdForScope(scope) }

  endIdForScope (scope) { return this.registry.endIdForScope(scope) }

  scopeForId (id) { return this.registry.scopeForId(id) }

  createRule (options) { return new Rule(this, this.registry, options) }

  createPattern (options) { return new Pattern(this, this.registry, options) }

  getMaxTokensPerLine () { return this.maxTokensPerLine }

  scopesFromStack (stack, rule, endPatternMatch) {
    const scopes = []
    for (let {scopeName, contentScopeName} of stack) {
      if (scopeName) { scopes.push(scopeName) }
      if (contentScopeName) { scopes.push(contentScopeName) }
    }

    // Pop the last content name scope if the end pattern at the top of the stack
    // was matched since only text between the begin/end patterns should have the
    // content name scope
    if (endPatternMatch && rule && rule.contentScopeName && rule === stack[stack.length - 1]) {
      scopes.pop()
    }

    return scopes
  }
}

class TokenizeLineResult {
  constructor (line, openScopeTags, tags, ruleStack, registry) {
    this.line = line
    this.openScopeTags = openScopeTags
    this.tags = tags
    this.ruleStack = ruleStack
    this.registry = registry
  }

  get tokens () {
    return this.registry.decodeTokens(this.line, this.tags, this.openScopeTags)
  }
}

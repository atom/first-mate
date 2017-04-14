import Scanner from './scanner'

export default class Rule {
  constructor (grammar, registry, {scopeName, contentScopeName, patterns, endPattern, applyEndPatternLast} = {}) {
    this.grammar = grammar
    this.registry = registry
    this.scopeName = scopeName
    this.contentScopeName = contentScopeName
    this.endPattern = endPattern
    this.applyEndPatternLast = applyEndPatternLast
    this.patterns = []
    for (let pattern of patterns || []) {
      if (!pattern.disabled) { this.patterns.push(this.grammar.createPattern(pattern)) }
    }

    if (this.endPattern && !this.endPattern.hasBackReferences) {
      if (this.applyEndPatternLast) {
        this.patterns.push(this.endPattern)
      } else {
        this.patterns.unshift(this.endPattern)
      }
    }

    this.scannersByBaseGrammarName = {}
    this.createEndPattern = null
    this.anchorPosition = -1
  }

  getIncludedPatterns (baseGrammar, included = []) {
    if (included.includes(this)) { return [] }

    included = included.concat([this])
    const allPatterns = []
    for (let pattern of this.patterns) {
      allPatterns.push(...pattern.getIncludedPatterns(baseGrammar, included))
    }
    return allPatterns
  }

  clearAnchorPosition () { this.anchorPosition = -1 }

  getScanner (baseGrammar) {
    let scanner = this.scannersByBaseGrammarName[baseGrammar.name]
    if (scanner) { return scanner }

    const patterns = this.getIncludedPatterns(baseGrammar)
    scanner = new Scanner(patterns)
    this.scannersByBaseGrammarName[baseGrammar.name] = scanner
    return scanner
  }

  scanInjections (ruleStack, line, position, firstLine) {
    const baseGrammar = ruleStack[0].rule.grammar
    const injections = baseGrammar.injections
    if (injections) {
      for (let scanner of injections.getScanners(ruleStack)) {
        const result = scanner.findNextMatch(line, firstLine, position, this.anchorPosition)
        if (result) { return result }
      }
    }
  }

  normalizeCaptureIndices (line, captureIndices) {
    const lineLength = line.length
    for (let capture of captureIndices) {
      capture.end = Math.min(capture.end, lineLength)
      capture.start = Math.min(capture.start, lineLength)
    }
  }

  findNextMatch (ruleStack, line, position, firstLine) {
    const lineWithNewline = `${line}\n`
    const baseGrammar = ruleStack[0].rule.grammar
    const results = []

    let scanner = this.getScanner(baseGrammar)
    let result = scanner.findNextMatch(lineWithNewline, firstLine, position, this.anchorPosition)
    if (result) {
      results.push(result)
    }

    result = this.scanInjections(ruleStack, lineWithNewline, position, firstLine)
    if (result) {
      for (let injection of baseGrammar.injections.injections) {
        if (injection.scanner === result.scanner) {
          if (injection.selector.getPrefix(this.grammar.scopesFromStack(ruleStack)) === 'L') {
            results.unshift(result)
          } else {
            // TODO: Prefixes can either be L, B, or R.
            // R is assumed to mean "right", which is the default (add to end of stack).
            // There's no documentation on B, however.
            results.push(result)
          }
        }
      }
    }

    let scopes = null
    for (let injectionGrammar of this.registry.injectionGrammars) {
      if (injectionGrammar === this.grammar) { continue }
      if (injectionGrammar === baseGrammar) { continue }
      if (scopes == null) { scopes = this.grammar.scopesFromStack(ruleStack) }
      if (injectionGrammar.injectionSelector.matches(scopes)) {
        scanner = injectionGrammar.getInitialRule().getScanner(injectionGrammar, position, firstLine)
        result = scanner.findNextMatch(lineWithNewline, firstLine, position, this.anchorPosition)
        if (result) {
          if (injectionGrammar.injectionSelector.getPrefix(scopes) === 'L') {
            results.unshift(result)
          } else {
            // TODO: Prefixes can either be L, B, or R.
            // R is assumed to mean "right", which is the default (add to end of stack).
            // There's no documentation on B, however.
            results.push(result)
          }
        }
      }
    }

    if (results.length > 1) {
      return results.sort((a, b) => {
        this.normalizeCaptureIndices(lineWithNewline, a.captureIndices)
        this.normalizeCaptureIndices(lineWithNewline, b.captureIndices)
        return a.captureIndices[0].start - b.captureIndices[0].start
      })[0]
    } else if (results.length === 1) {
      [result] = results
      this.normalizeCaptureIndices(lineWithNewline, result.captureIndices)
      return result
    }
  }

  getNextTags (ruleStack, line, position, firstLine) {
    const result = this.findNextMatch(ruleStack, line, position, firstLine)
    if (!result) { return null }

    const {index, captureIndices, scanner} = result
    const [firstCapture] = captureIndices
    const endPatternMatch = this.endPattern === scanner.patterns[index]
    const nextTags = scanner.handleMatch(result, ruleStack, line, this, endPatternMatch)
    if (nextTags) {
      return {nextTags, tagsStart: firstCapture.start, tagsEnd: firstCapture.end}
    }
  }

  getRuleToPush (line, beginPatternCaptureIndices) {
    if (this.endPattern.hasBackReferences) {
      const rule = this.grammar.createRule({scopeName: this.scopeName, contentScopeName: this.contentScopeName})
      rule.endPattern = this.endPattern.resolveBackReferences(line, beginPatternCaptureIndices)
      rule.patterns = [rule.endPattern, ...this.patterns]
      return rule
    } else {
      return this
    }
  }
}

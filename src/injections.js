import Scanner from './scanner'
import ScopeSelector from './scope-selector'

export default class Injections {
  constructor (grammar, injections = {}) {
    this.grammar = grammar
    this.injections = []
    this.scanners = {}
    for (let selector in injections) {
      const values = injections[selector]
      if (values && values.patterns && values.patterns.length > 0) {
        const patterns = []
        for (let regex of values.patterns) {
          const pattern = this.grammar.createPattern(regex)
          patterns.push(...pattern.getIncludedPatterns(grammar, patterns))
        }

        this.injections.push({
          selector: new ScopeSelector(selector),
          patterns
        })
      }
    }
  }

  getScanner (injection) {
    if (injection.scanner) { return injection.scanner }

    const scanner = new Scanner(injection.patterns)
    injection.scanner = scanner
    return scanner
  }

  getScanners (ruleStack) {
    if (this.injections.length === 0) { return [] }

    const scanners = []
    const scopes = this.grammar.scopesFromStack(ruleStack)
    for (let injection of this.injections) {
      if (injection.selector.matches(scopes)) {
        const scanner = this.getScanner(injection)
        scanners.push(scanner)
      }
    }
    return scanners
  }
}

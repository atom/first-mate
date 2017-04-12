import {OnigScanner} from 'oniguruma'

// Wrapper class for {OnigScanner} that caches them based on the presence of any
// anchor characters that change based on the current position being scanned.
//
// See {Pattern::replaceAnchor} for more details.
export default class Scanner {
  constructor (patterns = []) {
    this.patterns = patterns
    this.anchored = false
    for (let pattern of this.patterns) {
      if (pattern.anchored) {
        this.anchored = true
        break
      }
    }

    this.anchoredScanner = null
    this.firstLineAnchoredScanner = null
    this.firstLineScanner = null
    this.scanner = null
  }

  // Create a new {OnigScanner} with the given options.
  createScanner (firstLine, position, anchorPosition) {
    const patterns = this.patterns.map(pattern => pattern.getRegex(firstLine, position, anchorPosition))
    return new OnigScanner(patterns)
  }

  // Get the {OnigScanner} for the given position and options.
  getScanner (firstLine, position, anchorPosition) {
    if (!this.anchored) {
      if (!this.scanner) { this.scanner = this.createScanner(firstLine, position, anchorPosition) }
      return this.scanner
    }

    if (firstLine) {
      if (position === anchorPosition) {
        if (!this.firstLineAnchoredScanner) { this.firstLineAnchoredScanner = this.createScanner(firstLine, position, anchorPosition) }
        return this.firstLineAnchoredScanner
      } else {
        if (!this.firstLineScanner) { this.firstLineScanner = this.createScanner(firstLine, position, anchorPosition) }
        return this.firstLineScanner
      }
    } else if (position === anchorPosition) {
      if (!this.anchoredScanner) { this.anchoredScanner = this.createScanner(firstLine, position, anchorPosition) }
      return this.anchoredScanner
    } else {
      if (!this.scanner) { this.scanner = this.createScanner(firstLine, position, anchorPosition) }
      return this.scanner
    }
  }

  // Public: Find the next match on the line start at the given position
  //
  // * `line` The {String} being scanned.
  // * `firstLine` True if the first line is being scanned.
  // * `position` Numeric position to start scanning at.
  // * `anchorPosition` Numeric position of the last anchored match.
  //
  // Returns an {Object} with details about the match or null if no match found.
  findNextMatch (line, firstLine, position, anchorPosition) {
    const scanner = this.getScanner(firstLine, position, anchorPosition)
    const match = scanner.findNextMatchSync(line, position)
    if (match) {
      match.scanner = this
    }
    return match
  }

  // Public: Handle the given match by calling `handleMatch` on the
  // matched {Pattern}.
  //
  // * `match` An {Object} returned from a previous call to `findNextMatch`.
  // * `stack` An array of {Rule} objects.
  // * `line` The {String} being scanned.
  // * `rule` The {Rule} that matched.
  // * `endPatternMatch` True if the rule's end pattern matched.
  //
  // Returns an {Array} of tokens representing the match.
  handleMatch (match, stack, line, rule, endPatternMatch) {
    return this.patterns[match.index].handleMatch(stack, line, match.captureIndices, rule, endPatternMatch)
  }
}

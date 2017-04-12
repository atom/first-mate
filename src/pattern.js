/** @babel */

let Pattern;
import _ from 'underscore-plus';

const AllCustomCaptureIndicesRegex = /\$(\d+)|\${(\d+):\/(downcase|upcase)}/g;
const AllDigitsRegex = /\\\d+/g;
const DigitRegex = /\\\d+/;

export default Pattern = class Pattern {
  constructor(grammar, registry, options={}) {
    this.grammar = grammar;
    this.registry = registry;
    const {name, contentName, match, begin, end, patterns} = options;
    const {captures, beginCaptures, endCaptures, applyEndPatternLast} = options;
    {include: this.include, popRule: this.popRule, hasBackReferences: this.hasBackReferences} = options;

    this.pushRule = null;
    this.backReferences = null;
    this.scopeName = name;
    this.contentScopeName = contentName;

    if (match) {
      if (end || this.popRule && (this.hasBackReferences ? this.hasBackReferences : this.hasBackReferences = DigitRegex.test(match))) {
        this.match = match;
      } else {
        this.regexSource = match;
      }
      this.captures = captures;
    } else if (begin) {
      this.regexSource = begin;
      this.captures = beginCaptures ? beginCaptures : captures;
      const endPattern = this.grammar.createPattern({match: end, captures: endCaptures ? endCaptures : captures, popRule: true});
      this.pushRule = this.grammar.createRule({scopeName: this.scopeName, contentScopeName: this.contentScopeName, patterns, endPattern, applyEndPatternLast});
    }

    if (this.captures) {
      for (let group in this.captures) {
        const capture = this.captures[group];
        if (capture.patterns && capture.patterns.length > 0 && !capture.rule) {
          capture.scopeName = this.scopeName;
          capture.rule = this.grammar.createRule(capture);
        }
      }
    }

    this.anchored = this.hasAnchor();
  }

  getRegex(firstLine, position, anchorPosition) {
    if (this.anchored) {
      return this.replaceAnchor(firstLine, position, anchorPosition);
    } else {
      return this.regexSource;
    }
  }

  hasAnchor() {
    if (!this.regexSource) { return false; }
    let escape = false;
    for (let character of this.regexSource) {
      if (escape && ['A', 'G', 'z'].includes(character)) { return true; }
      escape = !escape && (character === '\\');
    }
    return false;
  }

  replaceAnchor(firstLine, offset, anchor) {
    const escaped = [];
    const placeholder = '\uFFFF';
    let escape = false;
    for (let character of this.regexSource) {
      if (escape) {
        switch (character) {
          case 'A':
            if (firstLine) {
              escaped.push(`\\${character}`);
            } else {
              escaped.push(placeholder);
            }
            break;
          case 'G':
            if (offset === anchor) {
              escaped.push(`\\${character}`);
            } else {
              escaped.push(placeholder);
            }
            break;
          case 'z':
            escaped.push('$(?!\n)(?<!\n)');
            break;
          default:
            escaped.push(`\\${character}`);
        }
        escape = false;
      } else if (character === '\\') {
        escape = true;
      } else {
        escaped.push(character);
      }
    }

    return escaped.join('');
  }

  resolveBackReferences(line, beginCaptureIndices) {
    const beginCaptures = [];

    for (let {start, end} of beginCaptureIndices) {
      beginCaptures.push(line.slice(start, end));
    }

    const resolvedMatch = this.match.replace(AllDigitsRegex, function(match) {
      const index = parseInt(match.slice(1));
      if (beginCaptures[index] != null) {
        return _.escapeRegExp(beginCaptures[index]);
      } else {
        return `\\${index}`;
      }
    });

    return this.grammar.createPattern({hasBackReferences: false, match: resolvedMatch, captures: this.captures, popRule: this.popRule});
  }

  ruleForInclude(baseGrammar, name) {
    const hashIndex = name.indexOf('#');
    if (hashIndex === 0) {
      return this.grammar.getRepository()[name.slice(1)];
    } else if (hashIndex >= 1) {
      const grammarName = name.slice(0, hashIndex);
      const ruleName = name.slice(hashIndex + 1);
      this.grammar.addIncludedGrammarScope(grammarName);
      const grammar = this.registry.grammarForScopeName(grammarName)
      return grammar ? grammar.getRepository([ruleName]) || undefined
    } else if (name === '$self') {
      return this.grammar.getInitialRule();
    } else if (name === '$base') {
      return baseGrammar.getInitialRule();
    } else {
      this.grammar.addIncludedGrammarScope(name);
      const grammar = this.registry.grammarForScopeName(name);
      return grammar ? grammar.getInitialRule() || undefined;
    }
  }

  getIncludedPatterns(baseGrammar, included) {
    if (this.include) {
      const rule = this.ruleForInclude(baseGrammar, this.include);
      const patterns = rule ? rule.getIncludedPatterns(baseGrammar, included) : undefined;
      return patterns ? patterns : [];
    } else {
      return [this];
    }
  }

  resolveScopeName(scopeName, line, captureIndices) {
    return scopeName.replace(AllCustomCaptureIndicesRegex, function(match, index, commandIndex, command) {
      const capture = captureIndices[parseInt(index ? index : commandIndex)];
      if (capture) {
        let replacement = line.substring(capture.start, capture.end);
        // Remove leading dots that would make the selector invalid
        while (replacement[0] === '.') { replacement = replacement.substring(1); }
        switch (command) {
          case 'downcase': return replacement.toLowerCase();
          case 'upcase':   return replacement.toUpperCase();
          default: return replacement;
        }
      } else {
        return match;
      }
    });
  }

  handleMatch(stack, line, captureIndices, rule, endPatternMatch) {
    const tags = [];

    const zeroWidthMatch = captureIndices[0].start === captureIndices[0].end;

    if (this.popRule) {
      // Pushing and popping a rule based on zero width matches at the same index
      // leads to an infinite loop. We bail on parsing if we detect that case here.
      if (zeroWidthMatch && _.last(stack).zeroWidthMatch && _.last(stack).rule.anchorPosition === captureIndices[0].end) {
        return false;
      }

      const {contentScopeName} = _.last(stack);
      if (contentScopeName) { tags.push(this.grammar.endIdForScope(contentScopeName)); }
    } else if (this.scopeName) {
      const scopeName = this.resolveScopeName(this.scopeName, line, captureIndices);
      tags.push(this.grammar.startIdForScope(scopeName));
    }

    if (this.captures) {
      tags.push(...this.tagsForCaptureIndices(line, _.clone(captureIndices), captureIndices, stack));
    } else {
      const {start, end} = captureIndices[0];
      if (end !== start) { tags.push(end - start); }
    }

    if (this.pushRule) {
      const ruleToPush = this.pushRule.getRuleToPush(line, captureIndices);
      ruleToPush.anchorPosition = captureIndices[0].end;
      const {contentScopeName} = ruleToPush;
      stack.push({rule: ruleToPush, scopeName, contentScopeName, zeroWidthMatch});
      if (contentScopeName) { tags.push(this.grammar.startIdForScope(contentScopeName)); }
    } else {
      let scopeName;
      if (this.popRule) { {scopeName} = stack.pop(); }
      if (scopeName) { tags.push(this.grammar.endIdForScope(scopeName)); }
    }

    return tags;
  }

  tagsForCaptureRule(rule, line, captureStart, captureEnd, stack) {
    const captureText = line.substring(captureStart, captureEnd);
    const {tags} = rule.grammar.tokenizeLine(captureText, [...stack, {rule}]);

    // only accept non empty tokens that don't exceed the capture end
    const openScopes = [];
    const captureTags = [];
    let offset = 0;
    for (let tag of tags) {
      if (tag < 0 || tag > 0 && offset < captureEnd) {
        captureTags.push(tag);
        if (tag >= 0) {
          offset += tag;
        } else {
          if (tag % 2 === 0) {
            openScopes.pop();
          } else {
            openScopes.push(tag);
          }
        }
      }
    }

    // close any scopes left open by matching this rule since we don't pass our stack
    while (openScopes.length > 0) {
      captureTags.push(openScopes.pop() - 1);
    }

    return captureTags;
  }

  // Get the tokens for the capture indices.
  //
  // line - The string being tokenized.
  // currentCaptureIndices - The current array of capture indices being
  //                         processed into tokens. This method is called
  //                         recursively and this array will be modified inside
  //                         this method.
  // allCaptureIndices - The array of all capture indices, this array will not
  //                     be modified.
  // stack - An array of rules.
  //
  // Returns a non-null but possibly empty array of tokens
  tagsForCaptureIndices(line, currentCaptureIndices, allCaptureIndices, stack) {
    let captureRule, captureTags, parentCaptureScope, scope;
    const parentCapture = currentCaptureIndices.shift();

    const tags = [];
    if (scope = this.captures[parentCapture.index] ? this.captures[parentCapture.index].name : undefined) {
      parentCaptureScope = this.resolveScopeName(scope, line, allCaptureIndices);
      tags.push(this.grammar.startIdForScope(parentCaptureScope));
    }

    if (captureRule = this.captures[parentCapture.index] ? this.captures[parentCapture.index].rule : undefined) {
      captureTags = this.tagsForCaptureRule(captureRule, line, parentCapture.start, parentCapture.end, stack);
      tags.push(...captureTags);
      // Consume child captures
      while (currentCaptureIndices.length && (currentCaptureIndices[0].start < parentCapture.end)) {
        currentCaptureIndices.shift();
      }
    } else {
      let previousChildCaptureEnd = parentCapture.start;
      while (currentCaptureIndices.length && currentCaptureIndices[0].start < parentCapture.end) {
        const childCapture = currentCaptureIndices[0];

        const emptyCapture = childCapture.end - childCapture.start === 0;
        const captureHasNoScope = !this.captures[childCapture.index];
        if (emptyCapture || captureHasNoScope) {
          currentCaptureIndices.shift();
          continue;
        }

        if (childCapture.start > previousChildCaptureEnd) {
          tags.push(childCapture.start - previousChildCaptureEnd);
        }

        captureTags = this.tagsForCaptureIndices(line, currentCaptureIndices, allCaptureIndices, stack);
        tags.push(...captureTags);
        previousChildCaptureEnd = childCapture.end;
      }

      if (parentCapture.end > previousChildCaptureEnd) {
        tags.push(parentCapture.end - previousChildCaptureEnd);
      }
    }

    if (parentCaptureScope) {
      if (tags.length > 1) {
        tags.push(this.grammar.endIdForScope(parentCaptureScope));
      } else {
        tags.pop();
      }
    }

    return tags;
  }
};

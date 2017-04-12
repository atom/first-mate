/** @babel */

class SegmentMatcher {
  constructor(segments) {
    this.segment = segments[0].join('') + segments[1].join('');
  }

  matches(scope) { return scope === this.segment; }

  getPrefix(scope) {}

  toCssSelector() {
    return this.segment.split('.').map(dotFragment => `.${dotFragment.replace(/\+/g, '\\+')}`).join('');
  }

  toCssSyntaxSelector() {
    return this.segment.split('.').map(dotFragment => `.syntax--${dotFragment.replace(/\+/g, '\\+')}`).join('');
  }
}

class TrueMatcher {
  constructor() {}

  matches() { return true; }

  getPrefix(scopes) {}

  toCssSelector() { return '*'; }

  toCssSyntaxSelector() { return '*'; }
}

class ScopeMatcher {
  constructor(first, others) {
    this.segments = [first];
    for (let segment of others) { this.segments.push(segment[1]); }
  }

  matches(scope) {
    const scopeSegments = scope.split('.');
    if (scopeSegments.length < this.segments.length) { return false; }

    for (let index = 0; index < this.segments.length; index++) {
      const segment = this.segments[index];
      if (!segment.matches(scopeSegments[index])) { return false; }
    }

    return true;
  }

  getPrefix(scope) {
    const scopeSegments = scope.split('.');
    if (scopeSegments.length < this.segments.length) { return false; }

    for (let index = 0; index < this.segments.length; index++) {
      const segment = this.segments[index];
      if (segment.matches(scopeSegments[index])) {
        if (segment.prefix) { return segment.prefix; }
      }
    }
  }

  toCssSelector() {
    return this.segments.map(matcher => matcher.toCssSelector()).join('');
  }

  toCssSyntaxSelector() {
    return this.segments.map(matcher => matcher.toCssSyntaxSelector()).join('');
  }
}

class GroupMatcher {
  constructor(prefix, selector) {
    this.prefix = prefix ? prefix[0] : undefined;
    this.selector = selector;
  }

  matches(scopes) { return this.selector.matches(scopes); }

  getPrefix(scopes) { if (this.selector.matches(scopes)) { return this.prefix; } }

  toCssSelector() { return this.selector.toCssSelector(); }

  toCssSyntaxSelector() { return this.selector.toCssSyntaxSelector(); }
}

class PathMatcher {
  constructor(prefix, first, others) {
    this.prefix = prefix ? prefix[0] : undefined;
    this.matchers = [first];
    for (let matcher of others) { this.matchers.push(matcher[1]); }
  }

  matches(scopes) {
    let index = 0;
    let matcher = this.matchers[index];
    for (let scope of scopes) {
      if (matcher.matches(scope)) { matcher = this.matchers[++index]; }
      if (!matcher) { return true; }
    }
    return false;
  }

  getPrefix(scopes) { if (this.matches(scopes)) { return this.prefix; } }

  toCssSelector() {
    return this.matchers.map(matcher => matcher.toCssSelector()).join(' ');
  }

  toCssSyntaxSelector() {
    return this.matchers.map(matcher => matcher.toCssSyntaxSelector()).join(' ');
  }
}

class OrMatcher {
  constructor(left, right) {
    this.left = left;
    this.right = right;
  }

  matches(scopes) { return this.left.matches(scopes) || this.right.matches(scopes); }

  getPrefix(scopes) { return this.left.getPrefix(scopes) || this.right.getPrefix(scopes); }

  toCssSelector() { return `${this.left.toCssSelector()}, ${this.right.toCssSelector()}`; }

  toCssSyntaxSelector() { return `${this.left.toCssSyntaxSelector()}, ${this.right.toCssSyntaxSelector()}`; }
}

class AndMatcher {
  constructor(left, right) {
    this.left = left;
    this.right = right;
  }

  matches(scopes) { return this.left.matches(scopes) && this.right.matches(scopes); }

  getPrefix(scopes) { if (this.left.matches(scopes) && this.right.matches(scopes)) { return this.left.getPrefix(scopes); } } // The right side can't have prefixes

  toCssSelector() {
    if (this.right instanceof NegateMatcher) {
      return `${this.left.toCssSelector()}${this.right.toCssSelector()}`;
    } else {
      return `${this.left.toCssSelector()} ${this.right.toCssSelector()}`;
    }
  }

  toCssSyntaxSelector() {
    if (this.right instanceof NegateMatcher) {
      return `${this.left.toCssSyntaxSelector()}${this.right.toCssSyntaxSelector()}`;
    } else {
      return `${this.left.toCssSyntaxSelector()} ${this.right.toCssSyntaxSelector()}`;
    }
  }
}

class NegateMatcher {
  constructor(matcher) {
    this.matcher = matcher;
  }

  matches(scopes) { return !this.matcher.matches(scopes); }

  getPrefix(scopes) {}

  toCssSelector() { return `:not(${this.matcher.toCssSelector()})`; }

  toCssSyntaxSelector() { return `:not(${this.matcher.toCssSyntaxSelector()})`; }
}

class CompositeMatcher {
  constructor(left, operator, right) {
    switch (operator) {
      case '|': this.matcher = new OrMatcher(left, right); break;
      case '&': this.matcher = new AndMatcher(left, right); break;
      case '-': this.matcher = new AndMatcher(left, new NegateMatcher(right)); break;
    }
  }

  matches(scopes) { return this.matcher.matches(scopes); }

  getPrefix(scopes) { return this.matcher.getPrefix(scopes); }

  toCssSelector() { return this.matcher.toCssSelector(); }

  toCssSyntaxSelector() { return this.matcher.toCssSyntaxSelector(); }
}

export { AndMatcher, CompositeMatcher, GroupMatcher, NegateMatcher, OrMatcher, PathMatcher, ScopeMatcher, SegmentMatcher, TrueMatcher };

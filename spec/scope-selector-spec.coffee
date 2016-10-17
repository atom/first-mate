ScopeSelector = require '../lib/scope-selector'

describe "ScopeSelector", ->
  describe ".matches(scopes)", ->
    it "matches the asterisk", ->
      expect(new ScopeSelector('*').matches(['a'])).toBeTruthy()
      expect(new ScopeSelector('*').matches(['b', 'c'])).toBeTruthy()
      expect(new ScopeSelector('a.*.c').matches(['a.b.c'])).toBeTruthy()
      expect(new ScopeSelector('a.*.c').matches(['a.b.c.d'])).toBeTruthy()
      expect(new ScopeSelector('a.*.c').matches(['a.b.d.c'])).toBeFalsy()

    it "matches segments", ->
      expect(new ScopeSelector('a').matches(['a'])).toBeTruthy()
      expect(new ScopeSelector('a').matches(['a.b'])).toBeTruthy()
      expect(new ScopeSelector('a.b').matches(['a.b.c'])).toBeTruthy()
      expect(new ScopeSelector('a').matches(['abc'])).toBeFalsy()
      expect(new ScopeSelector('a.b-c').matches(['a.b-c.d'])).toBeTruthy()
      expect(new ScopeSelector('a.b').matches(['a.b-d'])).toBeFalsy()
      expect(new ScopeSelector('c++').matches(['c++'])).toBeTruthy()
      expect(new ScopeSelector('c++').matches(['c'])).toBeFalsy()
      expect(new ScopeSelector('a_b_c').matches(['a_b_c'])).toBeTruthy()
      expect(new ScopeSelector('a_b_c').matches(['a_b'])).toBeFalsy()

    it "matches prefixes", ->
      expect(new ScopeSelector('R:g').matches(['g'])).toBeTruthy()
      expect(new ScopeSelector('R:g').matches(['R:g'])).toBeFalsy()

    it "matches disjunction", ->
      expect(new ScopeSelector('a | b').matches(['b'])).toBeTruthy()
      expect(new ScopeSelector('a|b|c').matches(['c'])).toBeTruthy()
      expect(new ScopeSelector('a|b|c').matches(['d'])).toBeFalsy()

    it "matches negation", ->
      expect(new ScopeSelector('a - c').matches(['a', 'b'])).toBeTruthy()
      expect(new ScopeSelector('a - c').matches(['a'])).toBeTruthy()
      expect(new ScopeSelector('-c').matches(['b'])).toBeTruthy()
      expect(new ScopeSelector('-c').matches(['c', 'b'])).toBeFalsy()
      expect(new ScopeSelector('a-b').matches(['a', 'b'])).toBeFalsy()
      expect(new ScopeSelector('a -b').matches(['a', 'b'])).toBeFalsy()
      expect(new ScopeSelector('a -c').matches(['a', 'b'])).toBeTruthy()
      expect(new ScopeSelector('a-c').matches(['a', 'b'])).toBeFalsy()

    it "matches conjunction", ->
      expect(new ScopeSelector('a & b').matches(['b', 'a'])).toBeTruthy()
      expect(new ScopeSelector('a&b&c').matches(['c'])).toBeFalsy()
      expect(new ScopeSelector('a&b&c').matches(['a', 'b', 'd'])).toBeFalsy()
      expect(new ScopeSelector('a & -b').matches(['a', 'b', 'd'])).toBeFalsy()
      expect(new ScopeSelector('a & -b').matches(['a', 'd'])).toBeTruthy()

    it "matches composites", ->
      expect(new ScopeSelector('a,b,c').matches(['b', 'c'])).toBeTruthy()
      expect(new ScopeSelector('a, b, c').matches(['d', 'e'])).toBeFalsy()
      expect(new ScopeSelector('a, b, c').matches(['d', 'c.e'])).toBeTruthy()
      expect(new ScopeSelector('a,').matches(['a', 'c'])).toBeTruthy()
      expect(new ScopeSelector('a,').matches(['b', 'c'])).toBeFalsy()

    it "matches groups", ->
      expect(new ScopeSelector('(a,b) | (c, d)').matches(['a'])).toBeTruthy()
      expect(new ScopeSelector('(a,b) | (c, d)').matches(['b'])).toBeTruthy()
      expect(new ScopeSelector('(a,b) | (c, d)').matches(['c'])).toBeTruthy()
      expect(new ScopeSelector('(a,b) | (c, d)').matches(['d'])).toBeTruthy()
      expect(new ScopeSelector('(a,b) | (c, d)').matches(['e'])).toBeFalsy()

    it "matches paths", ->
      expect(new ScopeSelector('a b').matches(['a', 'b'])).toBeTruthy()
      expect(new ScopeSelector('a b').matches(['b', 'a'])).toBeFalsy()
      expect(new ScopeSelector('a c').matches(['a', 'b', 'c', 'd', 'e'])).toBeTruthy()
      expect(new ScopeSelector('a b e').matches(['a', 'b', 'c', 'd', 'e'])).toBeTruthy()

    it "accepts a string scope parameter", ->
      expect(new ScopeSelector('a|b').matches('a')).toBeTruthy()
      expect(new ScopeSelector('a|b').matches('b')).toBeTruthy()
      expect(new ScopeSelector('a|b').matches('c')).toBeFalsy()
      expect(new ScopeSelector('test').matches('test')).toBeTruthy()

  describe ".getPrefix(scopes)", ->
    it "returns the prefix if it exists and if it matches the scopes", ->
      expect(new ScopeSelector('L:a').getPrefix('a')).toEqual 'L'
      expect(new ScopeSelector('B:a').getPrefix('a')).toEqual 'B'
      expect(new ScopeSelector('R:a').getPrefix('a')).toEqual 'R'
      expect(-> new ScopeSelector('Q:a').getPrefix('a')).toThrow()
      expect(new ScopeSelector('L:a').getPrefix('b')).toBeUndefined()
      expect(new ScopeSelector('a').getPrefix('a')).toBeUndefined()
      expect(new ScopeSelector('L:a b').getPrefix(['a', 'b'])).toEqual 'L'
      expect(-> new ScopeSelector('a L:b').getPrefix(['a', 'b'])).toThrow()
      expect(new ScopeSelector('L:(a | b)').getPrefix('a')).toEqual 'L'
      expect(new ScopeSelector('L:(a | b)').getPrefix('b')).toEqual 'L'
      expect(new ScopeSelector('L:a & b').getPrefix(['a', 'b'])).toEqual 'L'
      expect(new ScopeSelector('a & L:b').getPrefix(['a', 'b'])).toBeUndefined()
      expect(new ScopeSelector('L:a - b').getPrefix('a')).toEqual 'L'
      expect(new ScopeSelector('L:a - b').getPrefix(['a', 'b'])).toBeUndefined()
      expect(new ScopeSelector('L:a - b').getPrefix('b')).toBeUndefined()
      expect(new ScopeSelector('a - L:b').getPrefix('a')).toBeUndefined()
      expect(new ScopeSelector('a - L:b').getPrefix(['a', 'b'])).toBeUndefined()
      expect(new ScopeSelector('L:*').getPrefix('a')).toEqual 'L'
      expect(new ScopeSelector('L:a, b').getPrefix('a')).toEqual 'L'
      expect(new ScopeSelector('L:a, b').getPrefix('b')).toBeUndefined()
      expect(new ScopeSelector('L:a, R:b').getPrefix('a')).toEqual 'L'
      expect(new ScopeSelector('L:a, R:b').getPrefix('b')).toEqual 'R'

  describe ".toCssSelector()", ->
    it "converts the TextMate scope selector to a CSS selector", ->
      expect(new ScopeSelector('a b c').toCssSelector()).toBe '.a .b .c'
      expect(new ScopeSelector('a.b.c').toCssSelector()).toBe '.a.b.c'
      expect(new ScopeSelector('*').toCssSelector()).toBe '*'
      expect(new ScopeSelector('a - b').toCssSelector()).toBe '.a:not(.b)'
      expect(new ScopeSelector('a & b').toCssSelector()).toBe '.a .b'
      expect(new ScopeSelector('a & -b').toCssSelector()).toBe '.a:not(.b)'
      expect(new ScopeSelector('a | b').toCssSelector()).toBe '.a, .b'
      expect(new ScopeSelector('a - (b.c d)').toCssSelector()).toBe '.a:not(.b.c .d)'
      expect(new ScopeSelector('a, b').toCssSelector()).toBe '.a, .b'
      expect(new ScopeSelector('c++').toCssSelector()).toBe '.c\\+\\+'

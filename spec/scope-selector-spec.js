/* eslint-env mocha */

import {assert} from 'chai'

import ScopeSelector from '../lib/scope-selector'

describe('ScopeSelector', () => {
  describe('.matches(scopes)', () => {
    it('matches the asterisk', () => {
      assert.isOk(new ScopeSelector('*').matches(['a']))
      assert.isOk(new ScopeSelector('*').matches(['b', 'c']))
      assert.isOk(new ScopeSelector('a.*.c').matches(['a.b.c']))
      assert.isOk(new ScopeSelector('a.*.c').matches(['a.b.c.d']))
      assert.isNotOk(new ScopeSelector('a.*.c').matches(['a.b.d.c']))
    })

    it('matches segments', () => {
      assert.isOk(new ScopeSelector('a').matches(['a']))
      assert.isOk(new ScopeSelector('a').matches(['a.b']))
      assert.isOk(new ScopeSelector('a.b').matches(['a.b.c']))
      assert.isNotOk(new ScopeSelector('a').matches(['abc']))
      assert.isOk(new ScopeSelector('a.b-c').matches(['a.b-c.d']))
      assert.isNotOk(new ScopeSelector('a.b').matches(['a.b-d']))
      assert.isOk(new ScopeSelector('c++').matches(['c++']))
      assert.isNotOk(new ScopeSelector('c++').matches(['c']))
      assert.isOk(new ScopeSelector('a_b_c').matches(['a_b_c']))
      assert.isNotOk(new ScopeSelector('a_b_c').matches(['a_b']))
    })

    it('matches prefixes', () => {
      assert.isOk(new ScopeSelector('R:g').matches(['g']))
      assert.isNotOk(new ScopeSelector('R:g').matches(['R:g']))
    })

    it('matches disjunction', () => {
      assert.isOk(new ScopeSelector('a | b').matches(['b']))
      assert.isOk(new ScopeSelector('a|b|c').matches(['c']))
      assert.isNotOk(new ScopeSelector('a|b|c').matches(['d']))
    })

    it('matches negation', () => {
      assert.isOk(new ScopeSelector('a - c').matches(['a', 'b']))
      assert.isOk(new ScopeSelector('a - c').matches(['a']))
      assert.isOk(new ScopeSelector('-c').matches(['b']))
      assert.isNotOk(new ScopeSelector('-c').matches(['c', 'b']))
      assert.isNotOk(new ScopeSelector('a-b').matches(['a', 'b']))
      assert.isNotOk(new ScopeSelector('a -b').matches(['a', 'b']))
      assert.isOk(new ScopeSelector('a -c').matches(['a', 'b']))
      assert.isNotOk(new ScopeSelector('a-c').matches(['a', 'b']))
    })

    it('matches conjunction', () => {
      assert.isOk(new ScopeSelector('a & b').matches(['b', 'a']))
      assert.isNotOk(new ScopeSelector('a&b&c').matches(['c']))
      assert.isNotOk(new ScopeSelector('a&b&c').matches(['a', 'b', 'd']))
      assert.isNotOk(new ScopeSelector('a & -b').matches(['a', 'b', 'd']))
      assert.isOk(new ScopeSelector('a & -b').matches(['a', 'd']))
    })

    it('matches composites', () => {
      assert.isOk(new ScopeSelector('a,b,c').matches(['b', 'c']))
      assert.isNotOk(new ScopeSelector('a, b, c').matches(['d', 'e']))
      assert.isOk(new ScopeSelector('a, b, c').matches(['d', 'c.e']))
      assert.isOk(new ScopeSelector('a,').matches(['a', 'c']))
      assert.isNotOk(new ScopeSelector('a,').matches(['b', 'c']))
    })

    it('matches groups', () => {
      assert.isOk(new ScopeSelector('(a,b) | (c, d)').matches(['a']))
      assert.isOk(new ScopeSelector('(a,b) | (c, d)').matches(['b']))
      assert.isOk(new ScopeSelector('(a,b) | (c, d)').matches(['c']))
      assert.isOk(new ScopeSelector('(a,b) | (c, d)').matches(['d']))
      assert.isNotOk(new ScopeSelector('(a,b) | (c, d)').matches(['e']))
    })

    it('matches paths', () => {
      assert.isOk(new ScopeSelector('a b').matches(['a', 'b']))
      assert.isNotOk(new ScopeSelector('a b').matches(['b', 'a']))
      assert.isOk(new ScopeSelector('a c').matches(['a', 'b', 'c', 'd', 'e']))
      assert.isOk(new ScopeSelector('a b e').matches(['a', 'b', 'c', 'd', 'e']))
    })

    it('accepts a string scope parameter', () => {
      assert.isOk(new ScopeSelector('a|b').matches('a'))
      assert.isOk(new ScopeSelector('a|b').matches('b'))
      assert.isNotOk(new ScopeSelector('a|b').matches('c'))
      assert.isOk(new ScopeSelector('test').matches('test'))
    })
  })

  describe('.getPrefix(scopes)', () =>
    it('returns the prefix if it exists and if it matches the scopes', () => {
      assert.equal(new ScopeSelector('L:a').getPrefix('a'), 'L')
      assert.equal(new ScopeSelector('B:a').getPrefix('a'), 'B')
      assert.equal(new ScopeSelector('R:a').getPrefix('a'), 'R')
      assert.throws(() => new ScopeSelector('Q:a').getPrefix('a'))
      assert.equal(new ScopeSelector('L:a').getPrefix('b'), undefined)
      assert.equal(new ScopeSelector('a').getPrefix('a'), undefined)
      assert.equal(new ScopeSelector('L:a b').getPrefix(['a', 'b']), 'L')
      assert.throws(() => new ScopeSelector('a L:b').getPrefix(['a', 'b']))
      assert.equal(new ScopeSelector('L:(a | b)').getPrefix('a'), 'L')
      assert.equal(new ScopeSelector('L:(a | b)').getPrefix('b'), 'L')
      assert.equal(new ScopeSelector('L:a & b').getPrefix(['a', 'b']), 'L')
      assert.equal(new ScopeSelector('a & L:b').getPrefix(['a', 'b']), undefined)
      assert.equal(new ScopeSelector('L:a - b').getPrefix('a'), 'L')
      assert.equal(new ScopeSelector('L:a - b').getPrefix(['a', 'b']), undefined)
      assert.equal(new ScopeSelector('L:a - b').getPrefix('b'), undefined)
      assert.equal(new ScopeSelector('a - L:b').getPrefix('a'), undefined)
      assert.equal(new ScopeSelector('a - L:b').getPrefix(['a', 'b']), undefined)
      assert.equal(new ScopeSelector('L:*').getPrefix('a'), 'L')
      assert.equal(new ScopeSelector('L:a, b').getPrefix('a'), 'L')
      assert.equal(new ScopeSelector('L:a, b').getPrefix('b'), undefined)
      assert.equal(new ScopeSelector('L:a, R:b').getPrefix('a'), 'L')
      assert.equal(new ScopeSelector('L:a, R:b').getPrefix('b'), 'R')
    })
  )

  describe('.toCssSelector()', () =>
    it('converts the TextMate scope selector to a CSS selector', () => {
      assert.equal(new ScopeSelector('a b c').toCssSelector(), '.a .b .c')
      assert.equal(new ScopeSelector('a.b.c').toCssSelector(), '.a.b.c')
      assert.equal(new ScopeSelector('*').toCssSelector(), '*')
      assert.equal(new ScopeSelector('a - b').toCssSelector(), '.a:not(.b)')
      assert.equal(new ScopeSelector('a & b').toCssSelector(), '.a .b')
      assert.equal(new ScopeSelector('a & -b').toCssSelector(), '.a:not(.b)')
      assert.equal(new ScopeSelector('a | b').toCssSelector(), '.a, .b')
      assert.equal(new ScopeSelector('a - (b.c d)').toCssSelector(), '.a:not(.b.c .d)')
      assert.equal(new ScopeSelector('a, b').toCssSelector(), '.a, .b')
      assert.equal(new ScopeSelector('c++').toCssSelector(), '.c\\+\\+')
    })
  )

  describe('.toCssSyntaxSelector()', () =>
    it('converts the TextMate scope selector to a CSS selector prefixing it `syntax--`', () => {
      assert.equal(new ScopeSelector('a b c').toCssSyntaxSelector(), '.syntax--a .syntax--b .syntax--c')
      assert.equal(new ScopeSelector('a.b.c').toCssSyntaxSelector(), '.syntax--a.syntax--b.syntax--c')
      assert.equal(new ScopeSelector('*').toCssSyntaxSelector(), '*')
      assert.equal(new ScopeSelector('a - b').toCssSyntaxSelector(), '.syntax--a:not(.syntax--b)')
      assert.equal(new ScopeSelector('a & b').toCssSyntaxSelector(), '.syntax--a .syntax--b')
      assert.equal(new ScopeSelector('a & -b').toCssSyntaxSelector(), '.syntax--a:not(.syntax--b)')
      assert.equal(new ScopeSelector('a | b').toCssSyntaxSelector(), '.syntax--a, .syntax--b')
      assert.equal(new ScopeSelector('a - (b.c d)').toCssSyntaxSelector(), '.syntax--a:not(.syntax--b.syntax--c .syntax--d)')
      assert.equal(new ScopeSelector('a, b').toCssSyntaxSelector(), '.syntax--a, .syntax--b')
      assert.equal(new ScopeSelector('c++').toCssSyntaxSelector(), '.syntax--c\\+\\+')
    })
  )
})

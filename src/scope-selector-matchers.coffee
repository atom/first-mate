class SegmentMatcher
  constructor: (segments) ->
    @segment = segments[0].join('') + segments[1].join('')

  matches: (scope) -> scope is @segment

  getPrefix: (scope) ->

  toCssSelector: ->
    @segment.split('.').map((dotFragment) ->
      '.' + dotFragment.replace(/\+/g, '\\+')
    ).join('')

  toCssSyntaxSelector: ->
    @segment.split('.').map((dotFragment) ->
      '.syntax--' + dotFragment.replace(/\+/g, '\\+')
    ).join('')

class TrueMatcher
  constructor: ->

  matches: -> true

  getPrefix: (scopes) ->

  toCssSelector: -> '*'

  toCssSyntaxSelector: -> '*'

class ScopeMatcher
  constructor: (first, others) ->
    @segments = [first]
    @segments.push(segment[1]) for segment in others

  matches: (scope) ->
    lastDotIndex = 0
    for matcherSegment, matcherSegmentIndex in @segments
      break if lastDotIndex > scope.length

      nextDotIndex = scope.indexOf('.', lastDotIndex)
      nextDotIndex = scope.length if nextDotIndex is -1

      scopeSegment = scope.substring(lastDotIndex, nextDotIndex)
      return false unless matcherSegment.matches(scopeSegment)

      lastDotIndex = nextDotIndex + 1

    matcherSegmentIndex is @segments.length

  getPrefix: (scope) ->
    scopeSegments = scope.split('.')
    return false if scopeSegments.length < @segments.length

    for segment, index in @segments
      if segment.matches(scopeSegments[index])
        return segment.prefix if segment.prefix?

  toCssSelector: ->
    @segments.map((matcher) -> matcher.toCssSelector()).join('')

  toCssSyntaxSelector: ->
    @segments.map((matcher) -> matcher.toCssSyntaxSelector()).join('')

class GroupMatcher
  constructor: (prefix, selector) ->
    @prefix = prefix?[0]
    @selector = selector

  matches: (scopes) -> @selector.matches(scopes)

  getPrefix: (scopes) -> @prefix if @selector.matches(scopes)

  toCssSelector: -> @selector.toCssSelector()

  toCssSyntaxSelector: -> @selector.toCssSyntaxSelector()

class PathMatcher
  constructor: (prefix, first, others) ->
    @prefix = prefix?[0]
    @matchers = [first]
    @matchers.push(matcher[1]) for matcher in others

  matches: (scopes) ->
    index = 0
    matcher = @matchers[index]
    for scope in scopes
      matcher = @matchers[++index] if matcher.matches(scope)
      return true unless matcher?
    false

  getPrefix: (scopes) -> @prefix if @matches(scopes)

  toCssSelector: ->
    @matchers.map((matcher) -> matcher.toCssSelector()).join(' ')

  toCssSyntaxSelector: ->
    @matchers.map((matcher) -> matcher.toCssSyntaxSelector()).join(' ')

class OrMatcher
  constructor: (@left, @right) ->

  matches: (scopes) -> @left.matches(scopes) or @right.matches(scopes)

  getPrefix: (scopes) -> @left.getPrefix(scopes) or @right.getPrefix(scopes)

  toCssSelector: -> "#{@left.toCssSelector()}, #{@right.toCssSelector()}"

  toCssSyntaxSelector: -> "#{@left.toCssSyntaxSelector()}, #{@right.toCssSyntaxSelector()}"

class AndMatcher
  constructor: (@left, @right) ->

  matches: (scopes) -> @left.matches(scopes) and @right.matches(scopes)

  getPrefix: (scopes) -> @left.getPrefix(scopes) if @left.matches(scopes) and @right.matches(scopes) # The right side can't have prefixes

  toCssSelector: ->
    if @right instanceof NegateMatcher
      "#{@left.toCssSelector()}#{@right.toCssSelector()}"
    else
      "#{@left.toCssSelector()} #{@right.toCssSelector()}"

  toCssSyntaxSelector: ->
    if @right instanceof NegateMatcher
      "#{@left.toCssSyntaxSelector()}#{@right.toCssSyntaxSelector()}"
    else
      "#{@left.toCssSyntaxSelector()} #{@right.toCssSyntaxSelector()}"

class NegateMatcher
  constructor: (@matcher) ->

  matches: (scopes) -> not @matcher.matches(scopes)

  getPrefix: (scopes) ->

  toCssSelector: -> ":not(#{@matcher.toCssSelector()})"

  toCssSyntaxSelector: -> ":not(#{@matcher.toCssSyntaxSelector()})"

class CompositeMatcher
  constructor: (left, operator, right) ->
    switch operator
      when '|' then @matcher = new OrMatcher(left, right)
      when '&' then @matcher = new AndMatcher(left, right)
      when '-' then @matcher = new AndMatcher(left, new NegateMatcher(right))

  matches: (scopes) -> @matcher.matches(scopes)

  getPrefix: (scopes) -> @matcher.getPrefix(scopes)

  toCssSelector: -> @matcher.toCssSelector()

  toCssSyntaxSelector: -> @matcher.toCssSyntaxSelector()

module.exports = {
  AndMatcher
  CompositeMatcher
  GroupMatcher
  NegateMatcher
  OrMatcher
  PathMatcher
  ScopeMatcher
  SegmentMatcher
  TrueMatcher
}

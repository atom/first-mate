class SegmentMatcher
  constructor: (segments) ->
    @segment = segments[0].join('') + segments[1].join('')

  matches: (scope) -> scope is @segment

  getPrefix: (scope) ->

  toCssSelector: ->
    @segment.split('.').map((dotFragment) ->
      '.' + dotFragment.replace(/\+/g, '\\+')
    ).join('')

class TrueMatcher
  constructor: ->

  matches: -> true

  getPrefix: (scopes) ->

  toCssSelector: -> '*'

class ScopeMatcher
  constructor: (first, others) ->
    @segments = [first]
    @segments.push(segment[1]) for segment in others

  matches: (scope) ->
    scopeSegments = scope.split('.')
    return false if scopeSegments.length < @segments.length

    for segment, index in @segments
      return false unless segment.matches(scopeSegments[index])

    true

  getPrefix: (scope) ->
    scopeSegments = scope.split('.')
    return false if scopeSegments.length < @segments.length

    for segment, index in @segments
      if segment.matches(scopeSegments[index])
        return segment.prefix if segment.prefix?

  toCssSelector: ->
    @segments.map((matcher) -> matcher.toCssSelector()).join('')

class GroupMatcher
  constructor: (prefix, selector) ->
    @prefix = prefix?[0]
    @selector = selector

  matches: (scopes) -> @selector.matches(scopes)

  getPrefix: (scopes) -> @prefix

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

  getPrefix: (scopes) -> @prefix

  toCssSelector: ->
    @matchers.map((matcher) -> matcher.toCssSelector()).join(' ')

class OrMatcher
  constructor: (@left, @right) ->

  matches: (scopes) -> @left.matches(scopes) or @right.matches(scopes)

  getPrefix: (scopes) -> @left.getPrefix(scopes) or @right.getPrefix(scopes)

  toCssSelector: -> "#{@left.toCssSelector()}, #{@right.toCssSelector()}"

class AndMatcher
  constructor: (@left, @right) ->

  matches: (scopes) -> @left.matches(scopes) and @right.matches(scopes)

  getPrefix: (scopes) -> @left.getPrefix(scopes) or @right.getPrefix(scopes)

  toCssSelector: ->
    if @right instanceof NegateMatcher
      "#{@left.toCssSelector()}#{@right.toCssSelector()}"
    else
      "#{@left.toCssSelector()} #{@right.toCssSelector()}"

class NegateMatcher
  constructor: (@matcher) ->

  matches: (scopes) -> not @matcher.matches(scopes)

  getPrefix: (scopes) -> @matcher.getPrefix(scopes)

  toCssSelector: -> ":not(#{@matcher.toCssSelector()})"

class CompositeMatcher
  constructor: (left, operator, right) ->
    switch operator
      when '|' then @matcher = new OrMatcher(left, right)
      when '&' then @matcher = new AndMatcher(left, right)
      when '-' then @matcher = new AndMatcher(left, new NegateMatcher(right))

  matches: (scopes) -> @matcher.matches(scopes)

  getPrefix: (scopes) -> @matcher.getPrefix(scopes)

  toCssSelector: -> @matcher.toCssSelector()

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

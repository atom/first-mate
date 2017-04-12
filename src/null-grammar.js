/** @babel */

let NullGrammar;
import Grammar from './grammar';

// A grammar with no patterns that is always available from a {GrammarRegistry}
// even when it is completely empty.
export default NullGrammar = class NullGrammar extends Grammar {
  constructor(registry) {
    const name = 'Null Grammar';
    const scopeName = 'text.plain.null-grammar';
    super(registry, {name, scopeName});
  }

  getScore() { return 0; }
};

// Create event: "take me to the field" (note 53). A recipe Fix, or Review with gaps, lands on the exact field
// (scrolled to the middle, glowing, and focused when it's a text field), not just on the step. The ids match
// `fix.field` in src/lib/eventRecipe.js and the `data-field` anchors in CreateEvent.jsx.
// iOS twin: apps/ios/BanbeApp/Lib/CreateFieldGuide.swift (same ids, same order).

/** Field id -> step index (0 Host, 1 Basics, 2 When & where, 3 Tickets, 4 Photos). */
export const CREATE_FIELD_STEP = {
  hostName: 0,
  name: 1, description: 1, intro: 1, greeting: 1, categories: 1, keywords: 1, included: 1,
  // Event type facts (src/data/eventTypeProfiles.json): all in Basics, under Included.
  dietary: 1, dress_code: 1, lineup: 1, genre: 1, format: 1, artists: 1, medium: 1, brands: 1, experience: 1,
  entry_mode: 1, price_range: 1, alcohol: 1, min_age: 1,
  location: 2, date: 2,
  price: 3, seats: 3,
  photos: 4,
};

/** Every field that can be required, in the order the steps show them (type facts sit under Included).
 *  The single order behind firstMissingField below and createProgress.js `FIELD_ORDER`. */
export const CREATE_FIELD_ORDER = ['hostName', 'name', 'description', 'categories', 'included',
  'lineup', 'artists', 'brands', 'alcohol', 'min_age',
  'location', 'date', 'price', 'seats', 'photos'];

/** Fields that take typing, so a jump there also focuses them and opens the keyboard. */
export const CREATE_TEXT_FIELDS = new Set(['hostName', 'name', 'description', 'intro', 'greeting', 'keywords', 'location', 'price']);

export function stepOfField(field) {
  return Object.prototype.hasOwnProperty.call(CREATE_FIELD_STEP, field) ? CREATE_FIELD_STEP[field] : null;
}

export function isTextField(field) {
  return CREATE_TEXT_FIELDS.has(field);
}

/**
 * The first required field still missing, in the order the steps show them, or null when nothing is.
 * `missing` holds one boolean per id (true = still missing).
 */
export function firstMissingField(missing) {
  // Same order as the progress ring (was a separate list that left out price and the type facts).
  return CREATE_FIELD_ORDER.find(id => !!missing?.[id]) || null;
}

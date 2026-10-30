// Create event: ONE calculation behind the progress ring, "N steps left", "Still needed here" and the Review
// summary. Before this, each was its own hand-kept list and they drifted (iOS never asked for a valid price).
// Field ids and steps come from createFieldGuide.js. `required` is the active event type's list
// (src/lib/eventTypes.js), so a type can add or drop required fields without the ring, the count and the
// footer disagreeing.
// iOS twin: apps/ios/BanbeApp/Lib/CreateProgress.swift. Shared vectors: tests/fixtures/create-progress.json.
import { CREATE_FIELD_STEP, CREATE_FIELD_ORDER } from './createFieldGuide.js';

export const CREATE_STEP_COUNT = 5;

/** Every field that can be required, in the order the steps show them (type facts sit under Included). */
export const FIELD_ORDER = CREATE_FIELD_ORDER;

/** What an event of no known type needs (the generic event type, unchanged). */
export const DEFAULT_REQUIRED = ['hostName', 'name', 'description', 'categories', 'included', 'location', 'date', 'price', 'seats', 'photos'];

/**
 * `missing` maps a field id to true while that field is still missing.
 * Only fields in `required` count. A step is done once none of its required fields is missing, so a step with
 * nothing required (never the case for the 5 current steps) is done from the start.
 */
export function computeCreateProgress(missing, required = DEFAULT_REQUIRED) {
  const req = new Set(required);
  const gaps = FIELD_ORDER.filter(id => req.has(id) && !!missing?.[id]);
  const steps = Array.from({ length: CREATE_STEP_COUNT }, (_, index) => {
    const stepMissing = gaps.filter(id => CREATE_FIELD_STEP[id] === index);
    return { index, done: stepMissing.length === 0, missing: stepMissing };
  });
  const doneCount = steps.filter(x => x.done).length;
  return {
    steps,
    doneCount,
    total: CREATE_STEP_COUNT,
    percent: Math.round((doneCount / CREATE_STEP_COUNT) * 100),
    stepsLeft: CREATE_STEP_COUNT - doneCount,
    missing: gaps,
    firstMissing: gaps[0] || null,
  };
}

/**
 * Required fields that were missing before and are complete now (note 66): what earns the small ✓ and the
 * screen-reader "… done" line. Takes two `progress.missing` lists; order follows the second call's FIELD_ORDER.
 * A field that was never missing (already filled when the form opened) is not "newly" complete.
 */
export function newlyCompleted(prevMissing, nextMissing) {
  if (!Array.isArray(prevMissing)) return [];
  const now = new Set(nextMissing || []);
  return FIELD_ORDER.filter(id => prevMissing.includes(id) && !now.has(id));
}

/** The short label for a missing field, as shown after "Still needed: ". */
export function missingLabel(id, T, minPhotos) {
  switch (id) {
    case 'hostName': return T('tên host', 'host name');
    case 'name': return T('tên sự kiện', 'event name');
    case 'description': return T('mô tả', 'description');
    case 'categories': return T('danh mục', 'a category');
    case 'included': return T('mục bao gồm', 'an included item');
    case 'location': return T('địa chỉ gợi ý', 'a suggested address');
    case 'date': return T('ngày & giờ', 'date & time');
    case 'price': return T('giá vé hợp lệ', 'a valid price');
    case 'seats': return T('số chỗ', 'seats');
    case 'photos': return T(`ít nhất ${minPhotos} ảnh`, `at least ${minPhotos} photos`);
    case 'lineup': return T('đội hình', 'the lineup');
    case 'artists': return T('nghệ sĩ', 'the artists');
    case 'brands': return T('thương hiệu', 'the brands');
    case 'alcohol': return T('đồ uống có cồn', 'alcohol');
    case 'min_age': return T('độ tuổi tối thiểu', 'minimum age');
    default: return id;
  }
}

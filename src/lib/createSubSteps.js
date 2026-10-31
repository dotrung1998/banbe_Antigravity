// Note 69: Basics and Tickets had too many fields on one screen, so each is split into parts with their own small
// numbered bar (nested under the main step bar, styled differently). One part is on screen at a time; Back / Next walk
// the parts first, then the steps. "Take me to this field" (Fix, Still needed, Review with gaps) opens the part that
// holds the field. iOS twin: apps/ios/BanbeApp/Lib/CreateSubSteps.swift. Pure module.
import { stepOfField } from './createFieldGuide.js';

export const BASICS_STEP = 1;
export const TICKETS_STEP = 3;

export const BASICS_PARTS = [
  { id: 'name', vi: 'Tên', en: 'Name', fields: ['name'] },
  { id: 'story', vi: 'Mô tả', en: 'Story', fields: ['description', 'intro'] },
  { id: 'greeting', vi: 'Lời chào', en: 'Greeting', fields: ['greeting'] },
  { id: 'categories', vi: 'Hạng mục', en: 'Categories', fields: ['categories', 'keywords'] },
  // "Included" and every event-type fact (whichever types are picked).
  { id: 'details', vi: 'Chi tiết', en: 'Details', fields: ['included'] },
];

export const TICKETS_PARTS = [
  { id: 'price', vi: 'Giá', en: 'Price', fields: ['price'] },
  { id: 'seats', vi: 'Số chỗ', en: 'Seats', fields: ['seats'] },
  { id: 'privacy', vi: 'Quyền riêng tư', en: 'Privacy', fields: ['visibility'] },
  { id: 'criteria', vi: 'Ai được đặt', en: 'Who can book', fields: ['criteria'] },
];

/** The parts of a step; [] for steps that stay on one screen (Host, When & where, Photos). */
export function subStepParts(step) {
  return step === BASICS_STEP ? BASICS_PARTS : step === TICKETS_STEP ? TICKETS_PARTS : [];
}

/** The part that shows a field. Event-type facts (dietary, lineup, alcohol…) live in Basics › Details. */
export function partOfField(field, step) {
  const list = subStepParts(step);
  if (!list.length) return null;
  const i = list.findIndex(p => p.fields.includes(field));
  if (i >= 0) return i;
  if (step === BASICS_STEP && stepOfField(field) === BASICS_STEP) return list.length - 1;
  return null;
}

/**
 * Done = nothing required is missing in the part, and the host has seen it (a part with no required field is "done"
 * once visited, so the ✓ never claims work the host has not looked at).
 */
export function subStepDone(step, missing, visited) {
  return subStepParts(step).map((_, i) => !missing.some(f => partOfField(f, step) === i) && visited.has(i));
}

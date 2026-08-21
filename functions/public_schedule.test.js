"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {buildPublicSchedule} = require("./public_schedule");

test("public schedule includes availability but excludes private notes", () => {
  const result = buildPublicSchedule({
    availableDates: ["2026-08-24"],
    defaultWorkingHours: {from: "08:00", to: "16:00"},
    disabledDays: [6, 7],
    partialWorkDays: {"2026-08-24": [{from: "09:00", to: "12:00"}]},
    vacations: [{start: "2026-09-01", end: "2026-09-05"}],
    hideSchedule: false,
    allReminders: {"2026-08-24": [{text: "Private reminder"}]},
    dayNotes: {"2026-08-24": "Private note"},
    reminderDates: ["2026-08-24"],
  });

  assert.deepEqual(result, {
    availableDates: ["2026-08-24"],
    defaultWorkingHours: {from: "08:00", to: "16:00"},
    disabledDays: [6, 7],
    partialWorkDays: {"2026-08-24": [{from: "09:00", to: "12:00"}]},
    vacations: [{start: "2026-09-01", end: "2026-09-05"}],
  });
  assert.equal("allReminders" in result, false);
  assert.equal("dayNotes" in result, false);
});

test("public schedule handles missing data", () => {
  assert.deepEqual(buildPublicSchedule(null), {});
});

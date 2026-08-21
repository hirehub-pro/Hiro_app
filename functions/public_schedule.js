"use strict";

const PUBLIC_SCHEDULE_FIELDS = [
  "availableDates",
  "defaultWorkingHours",
  "disabledDays",
  "partialWorkDays",
  "vacations",
];

function buildPublicSchedule(schedule) {
  const source = schedule && typeof schedule === "object" ? schedule : {};
  const result = {};

  for (const field of PUBLIC_SCHEDULE_FIELDS) {
    if (Object.prototype.hasOwnProperty.call(source, field)) {
      result[field] = source[field];
    }
  }

  return result;
}

module.exports = {
  PUBLIC_SCHEDULE_FIELDS,
  buildPublicSchedule,
};

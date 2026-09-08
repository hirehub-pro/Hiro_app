"use strict";

const PROFILE_VIEW_TIME_ZONE = "Asia/Jerusalem";
const PROFILE_VIEW_SHARD_COUNT = 20;
const WEEKDAY_KEYS = [
  "sunday",
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
];

function normalizeProfileViewProfession(requestedProfession, professions) {
  const available = Array.isArray(professions) ? professions
      .map((profession) => String(profession ?? "").trim())
      .filter((profession) => profession.length > 0) : [];
  const requested = String(requestedProfession ?? "").trim().toLowerCase();
  const matching = available.find(
      (profession) => profession.toLowerCase() === requested,
  );
  return matching || available[0] || "General";
}

function profileViewPeriod(date, timeZone = PROFILE_VIEW_TIME_ZONE) {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone,
    weekday: "long",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(
      parts.filter((part) => part.type !== "literal")
          .map((part) => [part.type, part.value]),
  );
  const dayKey = values.weekday.toLowerCase();
  const dayIndex = WEEKDAY_KEYS.indexOf(dayKey);
  const localDateAsUtc = Date.UTC(
      Number(values.year),
      Number(values.month) - 1,
      Number(values.day),
  );
  const weekStart = new Date(localDateAsUtc - dayIndex * 24 * 60 * 60 * 1000);

  return {
    dayKey,
    weekKey: weekStart.toISOString().slice(0, 10),
    weekStart,
  };
}

function incrementWeeklyViewShard(existing, period) {
  const current = Object.fromEntries(WEEKDAY_KEYS.map((day) => [day, 0]));
  current.TVTW = 0;

  if (existing?.weekKey === period.weekKey) {
    for (const key of [...WEEKDAY_KEYS, "TVTW"]) {
      const value = existing[key];
      if (Number.isInteger(value) && value >= 0) current[key] = value;
    }
  }

  current[period.dayKey] += 1;
  current.TVTW += 1;
  return current;
}

module.exports = {
  PROFILE_VIEW_SHARD_COUNT,
  incrementWeeklyViewShard,
  normalizeProfileViewProfession,
  profileViewPeriod,
};

"use strict";

const PUBLIC_WORKER_PROFILE_COLLECTION = "publicWorkerProfiles";
const ENTITLED_SUBSCRIPTION_STATUSES = new Set([
  "active",
  "active_canceled",
]);

function asDate(value) {
  if (!value) return null;
  if (typeof value.toDate === "function") return value.toDate();
  if (value instanceof Date) return value;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function boundedString(value, maxLength) {
  return typeof value === "string" ? value.trim().slice(0, maxLength) : "";
}

function stringList(value, maxItems, maxLength) {
  if (!Array.isArray(value)) return [];
  return value
      .filter((item) => typeof item === "string")
      .map((item) => item.trim().slice(0, maxLength))
      .filter(Boolean)
      .slice(0, maxItems);
}

function finiteNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function publicCoordinate(value, min, max) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) return null;
  return parsed;
}

function safeSocialLinks(value) {
  const rawItems = Array.isArray(value) ? value :
    value && typeof value === "object" ? Object.values(value) : [];
  return rawItems
      .filter((item) => item && typeof item === "object")
      .map((item) => ({
        type: boundedString(item.type, 40),
        name: boundedString(item.name, 80),
        url: boundedString(item.url, 2048),
      }))
      .filter((item) => item.type && /^https:\/\//i.test(item.url))
      .slice(0, 20);
}

function safeProfessionStats(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const result = {};
  for (const [profession, rawStats] of Object.entries(value).slice(0, 50)) {
    if (!rawStats || typeof rawStats !== "object") continue;
    const key = boundedString(profession, 120);
    if (!key) continue;
    result[key] = {
      avg: Math.max(0, Math.min(5, finiteNumber(rawStats.avg))),
      count: Math.max(0, Math.trunc(finiteNumber(rawStats.count))),
    };
  }
  return result;
}

function hasSearchEntitlement(userData, now = new Date()) {
  if (userData?.isVIP === true) return true;
  const status = boundedString(userData?.subscriptionStatus, 40).toLowerCase();
  if (!ENTITLED_SUBSCRIPTION_STATUSES.has(status)) return false;

  const expiry = asDate(userData?.subscriptionExpiresAt) ||
    (asDate(userData?.subscriptionDate) ?
      new Date(asDate(userData.subscriptionDate).getTime() +
        30 * 24 * 60 * 60 * 1000) : null);
  return expiry == null || now.getTime() < expiry.getTime();
}

function buildPublicWorkerProfile(userId, userData, now = new Date()) {
  const role = boundedString(userData?.role, 40).toLowerCase();
  if (role !== "worker") return null;

  const lat = publicCoordinate(userData.lat, -90, 90);
  const lng = publicCoordinate(userData.lng, -180, 180);
  return {
    uid: userId,
    role: "worker",
    name: boundedString(userData.name, 100),
    email: boundedString(userData.email, 254),
    phone: boundedString(userData.phone, 32),
    optionalPhone: boundedString(userData.optionalPhone, 32),
    description: boundedString(userData.description, 2000),
    town: boundedString(userData.town, 120),
    profileImageUrl: boundedString(userData.profileImageUrl, 2048),
    professions: stringList(userData.professions, 50, 120),
    spokenLanguages: stringList(userData.spokenLanguages, 30, 80),
    socialLinks: safeSocialLinks(userData.socialLinks),
    avgRating: Math.max(0, Math.min(5, finiteNumber(userData.avgRating))),
    reviewCount: Math.max(0, Math.trunc(finiteNumber(userData.reviewCount))),
    professionStats: safeProfessionStats(userData.professionStats),
    workRadius: Math.max(0, finiteNumber(userData.workRadius)),
    lat,
    lng,
    hideSchedule: userData.hideSchedule === true,
    isIdVerified: userData.isIdVerified === true,
    isBusinessVerified: userData.isVerified === true ||
      userData.isBusinessVerified === true,
    isInsured: userData.isInsured === true,
    createdAt: userData.createdAt || null,
    isSearchVisible: hasSearchEntitlement(userData, now),
  };
}

module.exports = {
  PUBLIC_WORKER_PROFILE_COLLECTION,
  buildPublicWorkerProfile,
  hasSearchEntitlement,
};

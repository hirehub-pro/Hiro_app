"use strict";

function sumPublicProfileViews(ratingDocuments) {
  if (!Array.isArray(ratingDocuments)) return 0;

  return ratingDocuments.reduce((total, document) => {
    const value = Number(document?.totalViews);
    if (!Number.isFinite(value) || value <= 0) return total;
    return total + Math.trunc(value);
  }, 0);
}

module.exports = {sumPublicProfileViews};

"use strict";

function sumPublicProfileViews(viewDocuments) {
  if (!Array.isArray(viewDocuments)) return 0;

  return viewDocuments.reduce((total, document) => {
    const value = Number(document?.totalViews);
    if (!Number.isFinite(value) || value <= 0) return total;
    return total + Math.trunc(value);
  }, 0);
}

module.exports = {sumPublicProfileViews};

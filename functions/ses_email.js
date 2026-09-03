"use strict";

const nodemailer = require("nodemailer");

function requiredSetting(value, name) {
  const normalized = value == null ? "" : String(value).trim();
  if (!normalized) {
    throw new Error(`${name} is required to send email through Amazon SES.`);
  }
  return normalized;
}

function createSesTransport({
  region,
  smtpUsername,
  smtpPassword,
}) {
  const normalizedRegion = requiredSetting(region, "AWS_SES_REGION");
  return nodemailer.createTransport({
    host: `email-smtp.${normalizedRegion}.amazonaws.com`,
    port: 465,
    secure: true,
    auth: {
      user: requiredSetting(smtpUsername, "AWS_SES_SMTP_USERNAME"),
      pass: requiredSetting(smtpPassword, "AWS_SES_SMTP_PASSWORD"),
    },
  });
}

async function sendSesEmail(transport, message) {
  if (!transport || typeof transport.sendMail !== "function") {
    throw new TypeError("A valid Amazon SES mail transport is required.");
  }
  const info = await transport.sendMail(message);
  return {
    id: info?.response || info?.messageId || null,
  };
}

module.exports = {
  createSesTransport,
  sendSesEmail,
};

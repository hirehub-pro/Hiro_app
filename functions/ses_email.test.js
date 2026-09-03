"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");

const {createSesTransport, sendSesEmail} = require("./ses_email");

test("configures the TLS endpoint for the selected SES Region", () => {
  const transport = createSesTransport({
    region: "eu-central-1",
    smtpUsername: "smtp-user",
    smtpPassword: "smtp-password",
  });

  assert.equal(
      transport.options.host,
      "email-smtp.eu-central-1.amazonaws.com",
  );
  assert.equal(transport.options.port, 465);
  assert.equal(transport.options.secure, true);
  assert.equal(transport.options.auth.user, "smtp-user");
});

test("requires complete SES SMTP configuration", () => {
  assert.throws(() => createSesTransport({
    region: "eu-central-1",
    smtpUsername: "",
    smtpPassword: "smtp-password",
  }), /AWS_SES_SMTP_USERNAME/);
});

test("passes HTML, text, and attachments to the SES transport", async () => {
  let received;
  const result = await sendSesEmail({
    async sendMail(message) {
      received = message;
      return {response: "ses-message-id"};
    },
  }, {
    from: "Hiro <billing@example.com>",
    to: ["client@example.com"],
    subject: "Invoice",
    text: "Invoice attached",
    html: "<p>Invoice attached</p>",
    attachments: [{
      filename: "invoice.pdf",
      content: Buffer.from("pdf"),
    }],
  });

  assert.equal(result.id, "ses-message-id");
  assert.equal(received.to[0], "client@example.com");
  assert.equal(received.attachments[0].filename, "invoice.pdf");
});

test("rejects an invalid transport", async () => {
  await assert.rejects(
      () => sendSesEmail(null, {to: ["client@example.com"]}),
      /valid Amazon SES mail transport/,
  );
});

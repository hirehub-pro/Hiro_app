# Amazon SES setup

The Firebase Functions backend sends all application email through Amazon SES
API v2. Configure SES and the Firebase secrets before deploying these changes.

## 1. Configure Amazon SES

1. Choose an AWS Region and use the same Region for every step below.
2. In Amazon SES, verify the domain or email address that will appear in the
   `From` header.
3. Request production access for that Region. While SES is in the sandbox it
   can send only to verified recipients and is limited to 200 messages per day.
4. Open **SMTP settings** in the SES console and create dedicated SMTP
   credentials for this application. SES SMTP credentials are Region-specific
   and are not the same as a regular AWS access key.
5. Save the generated SMTP username and password in a password manager. Never
   add them to this repository or a `.env` file.

## 2. Set Firebase secrets

Run each command from the project root. The CLI prompts for the value without
writing it to the repository.

```bash
firebase functions:secrets:set AWS_SES_SMTP_USERNAME
firebase functions:secrets:set AWS_SES_SMTP_PASSWORD
firebase functions:secrets:set AWS_SES_REGION
firebase functions:secrets:set AWS_SES_FROM_EMAIL
```

`AWS_SES_FROM_EMAIL` may be an address such as `billing@example.com` or a named
sender such as `Hiro <billing@example.com>`. Its address or domain must be a
verified SES identity in `AWS_SES_REGION`.

## 3. Deploy the affected functions

```bash
firebase deploy --only functions:generateUniformExport,functions:sendInvoiceBuilderEmailCode,functions:emailSavedInvoice,functions:sendAccountingExportEmailHttp
```

Test an invoice-builder verification email, an invoice with a client email,
and an accounting export. After all sends are confirmed in SES, the old
`RESEND_API_KEY` and `RESEND_FROM_EMAIL` secrets can be destroyed.

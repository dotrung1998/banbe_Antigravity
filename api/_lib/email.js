import nodemailer from 'nodemailer';

// Resend (SMTP) is the primary provider. Gmail stays as a fallback so a deploy
// without RESEND_API_KEY keeps sending until the Vercel env var is set.
const DEFAULT_FROM = 'banbe <no-reply@banbe.app>';

function useResend() {
  return Boolean(process.env.RESEND_API_KEY);
}

let transporter;
function getTransporter() {
  if (!transporter) {
    transporter = useResend()
      ? nodemailer.createTransport({
          host: 'smtp.resend.com',
          port: 465,
          secure: true,
          auth: { user: 'resend', pass: process.env.RESEND_API_KEY },
        })
      : nodemailer.createTransport({
          host: 'smtp.gmail.com',
          port: 465,
          secure: true,
          auth: {
            user: process.env.GMAIL_USER,
            pass: process.env.GMAIL_APP_PASSWORD?.replace(/\s+/g, ''),
          },
        });
  }
  return transporter;
}

export function getMissingEmailVariables() {
  if (useResend()) return [];
  return [
    !process.env.GMAIL_USER && 'GMAIL_USER',
    !process.env.GMAIL_APP_PASSWORD && 'GMAIL_APP_PASSWORD',
  ].filter(Boolean);
}

export function sendEmail(message) {
  const from = useResend()
    ? process.env.EMAIL_FROM || DEFAULT_FROM
    : process.env.GMAIL_USER;
  return getTransporter().sendMail({ from, ...message });
}

// Kept so existing call sites don't need to change.
export const sendWithGmail = sendEmail;

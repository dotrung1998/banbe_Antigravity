import nodemailer from 'nodemailer';

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 465,
  secure: true,
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD?.replace(/\s+/g, ''),
  },
});

export function getMissingEmailVariables() {
  return [
    !process.env.GMAIL_USER && 'GMAIL_USER',
    !process.env.GMAIL_APP_PASSWORD && 'GMAIL_APP_PASSWORD',
  ].filter(Boolean);
}

export function sendWithGmail(message) {
  return transporter.sendMail({ from: process.env.GMAIL_USER, ...message });
}
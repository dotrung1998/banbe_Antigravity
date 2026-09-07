import nodemailer from 'nodemailer';

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_FIELD_LENGTH = 100_000;

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 465,
  secure: true,
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
  },
});

function isValidEmail(value) {
  return typeof value === 'string' && EMAIL_PATTERN.test(value.trim());
}

function getText(value) {
  return typeof value === 'string' ? value.trim() : '';
}

export default async function handler(req, res) {
  if (req.method === 'OPTIONS') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(204).end();
  }

  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST, OPTIONS');
    return res.status(405).json({ error: 'METHOD_NOT_ALLOWED' });
  }

  if (!process.env.GMAIL_USER || !process.env.GMAIL_APP_PASSWORD) {
    return res.status(503).json({ error: 'EMAIL_SERVICE_NOT_CONFIGURED' });
  }

  const body = req.body && typeof req.body === 'object' ? req.body : {};
  const to = getText(body.to);
  const subject = getText(body.subject);
  const text = getText(body.text);
  const html = getText(body.html);

  if (!isValidEmail(to)) {
    return res.status(400).json({ error: 'VALID_TO_EMAIL_REQUIRED' });
  }

  if (!subject || subject.length > 998) {
    return res.status(400).json({ error: 'VALID_SUBJECT_REQUIRED' });
  }

  if ((!text && !html) || text.length > MAX_FIELD_LENGTH || html.length > MAX_FIELD_LENGTH) {
    return res.status(400).json({ error: 'TEXT_OR_HTML_REQUIRED' });
  }

  try {
    const info = await transporter.sendMail({
      from: process.env.GMAIL_USER,
      to,
      subject,
      ...(text ? { text } : {}),
      ...(html ? { html } : {}),
    });

    return res.status(200).json({ sent: true, messageId: info.messageId });
  } catch (error) {
    console.error('Email delivery failed:', error);
    return res.status(502).json({ error: 'EMAIL_DELIVERY_FAILED' });
  }
}
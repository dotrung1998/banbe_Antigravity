# React + Vite

This template provides a minimal setup to get React working in Vite with HMR and some Oxlint rules.

Currently, two official plugins are available:

- [@vitejs/plugin-react](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react) uses [Oxc](https://oxc.rs)
- [@vitejs/plugin-react-swc](https://github.com/vitejs/vite-plugin-react/blob/main/packages/plugin-react-swc) uses [SWC](https://swc.rs/)

## React Compiler

The React Compiler is not enabled on this template because of its impact on dev & build performances. To add it, see [this documentation](https://react.dev/learn/react-compiler/installation).


## Authentication redirect

Set `VITE_AUTH_REDIRECT_URL` in the deployed app environment to the public app origin, for example `https://your-domain.example`. `VITE_SITE_URL` is accepted as a fallback name. If neither variable is set, local development uses the current browser origin.

## Email API

This Vite app uses a Vercel Function at `POST /api/send-email` rather than a Next.js App Router route. Install the mailer with:

```sh
npm install nodemailer
```

The project is JavaScript-only, so `@types/nodemailer` is not needed. For a TypeScript route, install it with `npm install -D @types/nodemailer`.

Set `GMAIL_USER`, `GMAIL_APP_PASSWORD`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, and `AUTH_REDIRECT_URL` in local `.env.local` and in Vercel Project Settings > Environment Variables. The app password is generated in Google Account > Security > 2-Step Verification > App passwords; regular Gmail passwords are not supported. Never expose `SUPABASE_SERVICE_ROLE_KEY` to the browser or prefix it with `VITE_`.

For the deployed app, add all five variables to Vercel's **Production** environment and redeploy. Vercel does not deploy `.env.local`. Copy the Supabase service-role key from Supabase Project Settings > API directly into Vercel; never commit it to `.env.example` or expose it to the browser.

Email sign-up and login links are generated server-side with Supabase Admin and delivered through Gmail by `POST /api/auth/send-email-link`. Supabase Auth does not send these email messages, so its two-per-hour email limit does not apply. Phone OTP continues to use the existing Supabase flow.

The request body must contain `to`, `subject`, and at least one of `text` or `html`:

```js
import { sendEmail } from './lib/sendEmail';

await sendEmail({
	to: 'recipient@example.com',
	subject: 'Hello',
	text: 'Message body',
});
```
## Expanding the Oxlint configuration

If you are developing a production application, we recommend using TypeScript with type-aware lint rules enabled. Check out the [TS template](https://github.com/vitejs/vite/tree/main/packages/create-vite/template-react-ts) for information on how to integrate TypeScript and Oxlint's TypeScript related rules in your project.

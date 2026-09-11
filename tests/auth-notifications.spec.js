// @ts-check
import { test, expect } from '@playwright/test';
import { setupToHome } from './helpers.js';

test.describe('Login & Signup Notification Messages', () => {
  test.beforeEach(async ({ page }) => {
    await setupToHome(page);
  });

  async function openLogin(page) {
    await page.getByText('Tài khoản').first().click();
    await expect(page.locator('[data-screen-label="Account"]')).toBeVisible({ timeout: 3000 });
    await page.getByText('Đăng nhập để lưu sự kiện và nhắn tin').click();
    await expect(page.locator('[data-screen-label="Login"]')).toBeVisible({ timeout: 3000 });
  }

  test('shows AUTH_ACCOUNT_NOT_FOUND for non-existent email on login', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 404,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_NOT_FOUND' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('nonexistent@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không tìm thấy tài khoản với email này/);
  });

  test('shows AUTH_ACCOUNT_NOT_FOUND for non-existent email on signup (falls through to generic)', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 404,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_NOT_FOUND' }),
      });
    });

    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="Tên hiển thị của bạn"]').fill('Nguyễn An');
    await page.locator('input[placeholder="ban@email.com"]').fill('nonexistent@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi mã đăng ký/);
  });

  test('shows AUTH_ACCOUNT_LOOKUP_FAILED when Supabase lookup errors', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể kiểm tra tài khoản lúc này/);
  });

  test('shows AUTH_EMAIL_DELIVERY_FAILED when Gmail fails', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_EMAIL_DELIVERY_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi email lúc này/);
  });

  test('shows AUTH_EMAIL_REQUEST_FAILED on generic email failure', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_EMAIL_REQUEST_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể xử lý yêu cầu email/);
  });

  test('shows AUTH_LINK_GENERATION_FAILED when code creation fails', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_LINK_GENERATION_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể tạo mã xác thực/);
  });

  test('shows AUTH_EMAIL_SERVICE_NOT_CONFIGURED when env vars are missing', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 503,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing: ['SUPABASE_SERVICE_ROLE_KEY'] }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Dịch vụ email chưa được cấu hình/);
  });

  test('shows generic login error for unknown error code on login', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'UNKNOWN_ERROR' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi mã đăng nhập/);
  });

  test('shows generic signup error for unknown error code on signup', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'UNKNOWN_ERROR' }),
      });
    });

    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="Tên hiển thị của bạn"]').fill('Nguyễn An');
    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi mã đăng ký/);
  });

  test('shows the code-entry step when the email is sent successfully', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ sent: true }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi mã tới email của bạn/);
    await expect(page.locator('input[placeholder="6-digit code"], input[placeholder="Mã 6 số"]')).toBeVisible();
  });

  test('points an existing email at the log-in tab instead of signing up again', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 409,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_EXISTS' }),
      });
    });

    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="Tên hiển thị của bạn"]').fill('Nguyễn An');
    await page.locator('input[placeholder="ban@email.com"]').fill('existing@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Email này đã có tài khoản/);
  });

  test('sends a sign-in code without asking for an account type', async ({ page }) => {
    await openLogin(page);

    /** @type {any} */
    let sentBody = null;
    await page.route('/api/auth/send-email-code', route => {
      sentBody = route.request().postDataJSON();
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ sent: true }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('returning@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi mã tới email của bạn/);
    expect(sentBody).toEqual({ email: 'returning@example.com', mode: 'login', locale: 'vi' });
  });

  test('requires a display name to sign up, and sends it with the request', async ({ page }) => {
    await openLogin(page);

    // No display name field on the log-in tab (the default).
    await expect(page.locator('input[placeholder="Tên hiển thị của bạn"]')).toHaveCount(0);
    await page.getByText('Đăng ký', { exact: true }).click();
    await expect(page.locator('input[placeholder="Tên hiển thị của bạn"]')).toBeVisible();

    /** @type {any} */
    let sentBody = null;
    await page.route('/api/auth/send-email-code', route => {
      sentBody = route.request().postDataJSON();
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ sent: true }),
      });
    });

    // Submitting without a name does nothing — no request is made.
    await page.locator('input[placeholder="ban@email.com"]').fill('newperson@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng ký/).click();
    expect(sentBody).toBeNull();

    await page.locator('input[placeholder="Tên hiển thị của bạn"]').fill('Nguyễn An');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi mã tới email của bạn/);
    expect(sentBody).toEqual({ email: 'newperson@example.com', mode: 'signup', locale: 'vi', displayName: 'Nguyễn An' });
  });

  test('does not claim the account is missing when the lookup itself failed', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('superdeutsche98@gmail.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    const login = page.locator('[data-screen-label="Login"]');
    await expect(login).toHaveText(/Không thể kiểm tra tài khoản lúc này/);
    await expect(login).not.toHaveText(/Không tìm thấy tài khoản với email này/);
  });

  test('rejects an empty or wrong code on the verify step', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-code', route => {
      route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ sent: true }) });
    });
    await page.route('**/auth/v1/verify*', route => {
      route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'otp_expired', error_description: 'Token has expired or is invalid' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi mã tới email của bạn/);

    await page.locator('[data-screen-label="Login"]').getByText(/Xác nhận/).click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Nhập mã đã gửi tới email của bạn/);

    await page.locator('input[inputmode="numeric"]').last().fill('000000');
    await page.locator('[data-screen-label="Login"]').getByText(/Xác nhận/).click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Mã không đúng hoặc đã hết hạn/);
  });

  test.describe('password method', () => {
    test('logs in with the wrong password shows a generic error', async ({ page }) => {
      await openLogin(page);
      await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();

      await page.route('**/auth/v1/token*', route => {
        route.fulfill({
          status: 400,
          contentType: 'application/json',
          body: JSON.stringify({ error: 'invalid_grant', error_description: 'Invalid login credentials' }),
        });
      });

      await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
      await page.locator('input[placeholder="Password"], input[placeholder="Mật khẩu"]').first().fill('wrongpassword');
      // "Đăng nhập" also labels the (already-active) Login tab above the
      // form — the submit button is the same text lower in the DOM.
      await page.locator('[data-screen-label="Login"]').getByText('Đăng nhập', { exact: true }).last().click();

      await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Sai email hoặc mật khẩu/);
    });

    test('requires matching passwords to sign up', async ({ page }) => {
      await openLogin(page);
      await page.getByText('Đăng ký', { exact: true }).click();
      await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();

      /** @type {any} */
      let sentBody = null;
      await page.route('/api/auth/signup-password', route => {
        sentBody = route.request().postDataJSON();
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ sent: true }) });
      });

      await page.locator('input[placeholder="Tên hiển thị của bạn"]').fill('Nguyễn An');
      await page.locator('input[placeholder="ban@email.com"]').fill('newperson@example.com');
      await page.locator('input[placeholder="Password"], input[placeholder="Mật khẩu"]').first().fill('correcthorse1');
      await page.locator('input[placeholder="Confirm password"], input[placeholder="Nhập lại mật khẩu"]').fill('differentpassword');
      await page.locator('[data-screen-label="Login"]').getByText('Tạo tài khoản', { exact: true }).click();

      expect(sentBody).toBeNull();
      await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Mật khẩu xác nhận không khớp/);
    });

    test('sends a password sign-up request and shows the confirmation code step', async ({ page }) => {
      await openLogin(page);
      await page.getByText('Đăng ký', { exact: true }).click();
      await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();

      /** @type {any} */
      let sentBody = null;
      await page.route('/api/auth/signup-password', route => {
        sentBody = route.request().postDataJSON();
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ sent: true }) });
      });

      await page.locator('input[placeholder="Tên hiển thị của bạn"]').fill('Nguyễn An');
      await page.locator('input[placeholder="ban@email.com"]').fill('newperson@example.com');
      await page.locator('input[placeholder="Password"], input[placeholder="Mật khẩu"]').first().fill('correcthorse1');
      await page.locator('input[placeholder="Confirm password"], input[placeholder="Nhập lại mật khẩu"]').fill('correcthorse1');
      await page.locator('[data-screen-label="Login"]').getByText('Tạo tài khoản', { exact: true }).click();

      expect(sentBody).toEqual({ email: 'newperson@example.com', password: 'correcthorse1', displayName: 'Nguyễn An', locale: 'vi' });
      await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi mã tới email của bạn/);
    });

    test('forgot-password always shows the same generic confirmation', async ({ page }) => {
      await openLogin(page);
      await page.locator('[data-screen-label="Login"]').getByText('Mật khẩu', { exact: true }).click();

      /** @type {any} */
      let sentBody = null;
      await page.route('/api/auth/send-password-reset', route => {
        sentBody = route.request().postDataJSON();
        route.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify({ sent: true }) });
      });

      await page.locator('input[placeholder="ban@email.com"]').fill('whoever@example.com');
      await page.locator('[data-screen-label="Login"]').getByText(/Quên mật khẩu/).click();

      expect(sentBody).toEqual({ email: 'whoever@example.com' });
      await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/một email đặt lại mật khẩu vừa được gửi|a password reset email was just sent/);
    });
  });

  test('shows Zalo not available error', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Tiếp tục với Zalo').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Zalo chưa khả dụng/);
  });

  test('shows Facebook not available error', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Facebook').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Facebook chưa khả dụng/);
  });

  test('shows Instagram not available error', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Instagram').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Instagram chưa khả dụng/);
  });

  test('shows phone required error when sending OTP without phone number', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Gửi OTP').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Nhập số điện thoại trước/);
  });

  test('shows OTP code required error when verifying without code', async ({ page }) => {
    await openLogin(page);

    await page.route('**/auth/v1/otp', async route => {
      const req = route.request();
      const body = JSON.parse(req.postData() || '{}');
      if (!body.token) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ data: { session: null, user: null, message: 'OTP sent' }, error: null }),
        });
      } else {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify({ data: { session: { access_token: 'test', user: { id: 'test' } }, user: { id: 'test' } }, error: null }),
        });
      }
    });

    await page.locator('input[placeholder="+84 901 234 567"]').fill('+84901234567');
    await page.locator('[data-screen-label="Login"]').getByText('Gửi OTP').click();
    await page.locator('[data-screen-label="Login"]').getByText('Xác nhận').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Nhập mã OTP/);
  });
});

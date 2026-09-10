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

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 404,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_NOT_FOUND' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('nonexistent@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không tìm thấy tài khoản với email này/);
  });

  test('shows AUTH_ACCOUNT_NOT_FOUND for non-existent email on signup (falls through to generic)', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 404,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_NOT_FOUND' }),
      });
    });

    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="ban@email.com"]').fill('nonexistent@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi link đăng ký/);
  });

  test('shows AUTH_ACCOUNT_LOOKUP_FAILED when Supabase lookup errors', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể kiểm tra tài khoản lúc này/);
  });

  test('shows AUTH_EMAIL_DELIVERY_FAILED when Gmail fails', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_EMAIL_DELIVERY_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi email lúc này/);
  });

  test('shows AUTH_EMAIL_REQUEST_FAILED on generic email failure', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_EMAIL_REQUEST_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể xử lý yêu cầu email/);
  });

  test('shows AUTH_LINK_GENERATION_FAILED when link creation fails', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_LINK_GENERATION_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể tạo liên kết xác thực/);
  });

  test('shows AUTH_EMAIL_SERVICE_NOT_CONFIGURED when env vars are missing', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 503,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_EMAIL_SERVICE_NOT_CONFIGURED', missing: ['SUPABASE_SERVICE_ROLE_KEY'] }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Dịch vụ email chưa được cấu hình/);
  });

  test('shows generic login error for unknown error code on login', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'UNKNOWN_ERROR' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi link đăng nhập/);
  });

  test('shows generic signup error for unknown error code on signup', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'UNKNOWN_ERROR' }),
      });
    });

    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không thể gửi link đăng ký/);
  });

  test('shows success message when email is sent successfully', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ sent: true }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi link đăng nhập/);
  });

  test('points an existing email at the log-in tab instead of signing up again', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 409,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_EXISTS' }),
      });
    });

    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="ban@email.com"]').fill('existing@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Email này đã có tài khoản/);
  });

  test('sends a sign-in link without asking for an account type', async ({ page }) => {
    await openLogin(page);

    /** @type {any} */
    let sentBody = null;
    await page.route('/api/auth/send-email-link', route => {
      sentBody = route.request().postDataJSON();
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ sent: true }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('returning@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi link đăng nhập/);
    expect(sentBody).toEqual({ email: 'returning@example.com', mode: 'login' });
  });

  test('does not claim the account is missing when the lookup itself failed', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 502,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'AUTH_ACCOUNT_LOOKUP_FAILED' }),
      });
    });

    await page.locator('input[placeholder="ban@email.com"]').fill('superdeutsche98@gmail.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng nhập/).click();

    const login = page.locator('[data-screen-label="Login"]');
    await expect(login).toHaveText(/Không thể kiểm tra tài khoản lúc này/);
    await expect(login).not.toHaveText(/Không tìm thấy tài khoản với email này/);
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

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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Không tìm thấy tài khoản với email này/);
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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

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

  test('shows admin signup block when admin account type is selected', async ({ page }) => {
    await openLogin(page);

    await page.getByText('Quản trị viên', { exact: true }).click();
    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="ban@email.com"]').fill('test@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Admin accounts are provisioned by banbe/);
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
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi mã đăng nhập/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Đã gửi link đăng nhập/);
  });

  test('shows role mismatch error for existing participant trying organizer signup', async ({ page }) => {
    await openLogin(page);

    await page.route('/api/auth/send-email-link', route => {
      route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          error: 'AUTH_ROLE_MISMATCH',
          message: 'This email is registered as a participant. To continue as an organizer, please complete the organizer registration process.',
          existingRole: 'participant',
        }),
      });
    });

    await page.getByText('Người tổ chức', { exact: true }).click();
    await page.getByText('Đăng ký', { exact: true }).click();
    await page.locator('input[placeholder="ban@email.com"]').fill('existing@example.com');
    await page.locator('[data-screen-label="Login"]').getByText(/Gửi link đăng ký/).click();

    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/registered as a participant/);
  });

  test('shows Zalo not available error', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Tiếp tục với Zalo').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Zalo login is not available yet/);
  });

  test('shows Facebook not available error', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Facebook').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Facebook login is not available yet/);
  });

  test('shows Instagram not available error', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Instagram').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Instagram login is not available yet/);
  });

  test('shows phone required error when sending OTP without phone number', async ({ page }) => {
    await openLogin(page);
    await page.locator('[data-screen-label="Login"]').getByText('Gửi OTP').click();
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Enter your phone number first/);
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
    await expect(page.locator('[data-screen-label="Login"]')).toHaveText(/Enter the OTP code/);
  });
});

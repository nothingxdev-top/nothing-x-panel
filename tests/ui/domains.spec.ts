import { test, expect } from '@playwright/test';

test.describe('Domains Page (/server/<id>/domains)', () => {
  test('Card mounts deterministically and is visible with all form controls', async ({ page }) => {
    const consoleErrors: string[] = [];
    page.on('console', msg => {
      if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    await page.goto('/server/test-srv-123/domains');
    await page.waitForLoadState('domcontentloaded');

    // Verify card is mounted and visible
    const card = page.locator('#np-domain-manager-card');
    await expect(card).toBeVisible({ timeout: 5000 });

    // Verify title and header exist
    await expect(card.locator('h3')).toContainText('CUSTOM DOMAINS & PORT ROUTING');

    // Verify form inputs exist
    const domainInput = page.locator('#np-domain-input');
    const portSelect = page.locator('#np-port-select');
    const sslToggle = page.locator('#np-ssl-toggle');

    await expect(domainInput).toBeVisible();
    await expect(portSelect).toBeAttached();
    await expect(sslToggle).toBeAttached();

    // Verify domain list renders loaded domains
    const domainLinks = page.locator('#np-domains-list a');
    await expect(domainLinks.first()).toContainText('play.example.com');

    // Zero console errors
    expect(consoleErrors.length).toBe(0);
  });

  test('Simulated API error renders visible error banner and not a blank page', async ({ page }) => {
    // Navigate to server that triggers a 500 API response
    await page.goto('/server/error-srv-999/domains');
    await page.waitForLoadState('domcontentloaded');

    const card = page.locator('#np-domain-manager-card');
    await expect(card).toBeVisible({ timeout: 5000 });

    // Verify visible error state in domains list
    const errorBanner = page.locator('#np-domains-list > div');
    await expect(errorBanner).toBeVisible();
    const errorText = (await errorBanner.textContent()) || '';
    expect(errorText.toLowerCase()).toContain('unable to load domains');
  });

  test('Client-side RFC 1035 domain validation rejects invalid domain inputs', async ({ page }) => {
    await page.goto('/server/test-srv-123/domains');
    await page.waitForSelector('#np-domain-manager-card');

    const domainInput = page.locator('#np-domain-input');
    const addBtn = page.locator('#np-btn-add-domain');
    const msgBox = page.locator('#np-domain-msg');

    // Type invalid domain name with forbidden characters
    await domainInput.fill('invalid_domain!@#.com');
    await addBtn.click();

    // Message box must display validation error
    await expect(msgBox).toBeVisible();
    await expect(msgBox).toContainText('Please enter a valid domain name');
  });
});

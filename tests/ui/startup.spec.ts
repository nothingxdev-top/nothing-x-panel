import { test, expect } from '@playwright/test';

test.describe('Startup Settings Page (/server/<id>/startup)', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/server/test-srv-123/startup');
    await page.waitForLoadState('domcontentloaded');
  });

  test('Startup Command text has computed text-transform: none and preserves exact casing', async ({ page }) => {
    const cmdParagraph = page.locator('div[class*="StartupContainer"] p[class*="font-mono"]');
    await expect(cmdParagraph).toBeVisible();

    // Verify computed text-transform is 'none'
    const textTransform = await cmdParagraph.evaluate(el => window.getComputedStyle(el).textTransform);
    expect(textTransform).toBe('none');

    // Verify DOM text preserves lowercase bash syntax (not uppercase)
    const textContent = (await cmdParagraph.textContent()) || '';
    expect(textContent).toContain('if [[ -d .git ]]');
    expect(textContent).toContain('/usr/local/bin/npm install');
    expect(textContent).not.toContain('IF [[ -D .GIT ]]');
  });

  test('Page has no horizontal scrollbar across viewports', async ({ page }) => {
    const hasHorizontalOverflow = await page.evaluate(() => {
      return document.documentElement.scrollWidth > window.innerWidth;
    });
    expect(hasHorizontalOverflow).toBe(false);
  });

  test('Startup Command and Docker Image cards are stacked vertically full-width', async ({ page }) => {
    const cmdCard = page.locator('#startup-command-card');
    const dockerCard = page.locator('#docker-image-card');

    await expect(cmdCard).toBeVisible();
    await expect(dockerCard).toBeVisible();

    const cmdBox = await cmdCard.boundingBox();
    const dockerBox = await dockerCard.boundingBox();

    expect(cmdBox).not.toBeNull();
    expect(dockerBox).not.toBeNull();

    if (cmdBox && dockerBox) {
      // Docker Image card must be positioned below Startup Command card (stacked vertically)
      expect(dockerBox.y).toBeGreaterThanOrEqual(cmdBox.y + cmdBox.height - 2);
    }
  });

  test('Docker Image custom select is not clipped at top or sides', async ({ page }) => {
    const selectTrigger = page.locator('.np-custom-select-trigger, div[class*="TitledGreyBox"] select');
    await expect(selectTrigger.first()).toBeVisible();

    const box = await selectTrigger.first().boundingBox();
    expect(box).not.toBeNull();
    if (box) {
      // Must have positive height and width
      expect(box.height).toBeGreaterThan(30);
      expect(box.width).toBeGreaterThan(100);
    }
  });
});

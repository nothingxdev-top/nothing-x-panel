import { test, expect } from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';

test.describe('Visual Glitch Regression & Accessibility', () => {
  test('Active navigation tab underline is theme purple (#C268F2)', async ({ page }) => {
    await page.goto('/server/test-srv-123/domains');
    await page.waitForLoadState('domcontentloaded');

    const activeTab = page.locator('nav a.active, div[class*="SubNavigation"] a.active').first();
    await expect(activeTab).toBeVisible();

    const styles = await activeTab.evaluate(el => {
      const computed = window.getComputedStyle(el);
      return {
        borderColor: computed.borderBottomColor || computed.borderColor,
        color: computed.color,
      };
    });

    // #C268F2 in RGB is rgb(194, 104, 242)
    expect(styles.borderColor).toBe('rgb(194, 104, 242)');
  });

  test('Background gradient is continuous without horizontal line or tiling at y=537px', async ({ page }) => {
    await page.goto('/server/test-srv-123/startup');
    await page.waitForLoadState('domcontentloaded');

    const bgProperties = await page.evaluate(() => {
      const bodyStyle = window.getComputedStyle(document.body);
      const htmlStyle = window.getComputedStyle(document.documentElement);
      return {
        attachment: bodyStyle.backgroundAttachment,
        repeat: bodyStyle.backgroundRepeat,
        size: bodyStyle.backgroundSize,
        image: bodyStyle.backgroundImage,
        bgColor: bodyStyle.backgroundColor,
        htmlBg: htmlStyle.backgroundColor,
      };
    });

    // Must be fixed attachment, no-repeat, and cover to eliminate the y=537px tile line
    expect(bgProperties.attachment).toBe('fixed');
    expect(bgProperties.repeat).toBe('no-repeat');
    expect(bgProperties.size).toBe('cover');
    expect(bgProperties.image).toContain('radial-gradient');
  });

  test('Color contrast meets WCAG AA standards (>= 4.5:1)', async ({ page }) => {
    await page.goto('/server/test-srv-123/startup');
    await page.waitForLoadState('domcontentloaded');

    // Run axe accessibility analysis specifically focusing on color contrast
    const accessibilityScanResults = await new AxeBuilder({ page })
      .withRules(['color-contrast'])
      .analyze();

    // Verify contrast violations are empty
    expect(accessibilityScanResults.violations).toEqual([]);
  });
});

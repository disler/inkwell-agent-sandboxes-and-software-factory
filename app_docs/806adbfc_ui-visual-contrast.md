# UI Visual Contrast & Accessibility Enhancements

## Overview

This change audits and improves visual contrast and focus indicators across the UI to comply with WCAG 2.1 AA standards (minimum 4.5:1 contrast ratio for normal text) while preserving the dark theme aesthetic. It also adds automated regression tests to verify CSS variable contrast ratios programmatically.

## Key Changes

### 1. Style Variable & Contrast Enhancements (`apps/inkwell/public/style.css`)
- **Faint Text (`--text-faint`)**: Increased luminance from `#565d68` to `#8b949e`. Resolves low-contrast issues on timestamps (`.post-time`), metadata (`.meta`), goal labels, input placeholders, draft indicators, and empty state text against dark backgrounds (`#0d1117` and `#090c11`).
- **Dimmed Text (`--text-dim`)**: Increased luminance from `#7d8590` to `#a3b0c2`. Improves legibility for buttons (`.btn`, `.new-btn`), sidebar post items, goal progress percentage, clear search icon, and keyboard shortcut hints (`kbd`, `.key-hint`).
- **Borders (`--border`)**: Darkened/sharpened border color from `#1b212b` to `#303846`. Provides clear definition for input borders (`.search-input`, `.goal-input`), dividers, code blocks, and modal overlays.
- **Interactive Focus States**: Added `:focus-visible` styles with a 2px accent outline and 1px offset for `.btn`, `.new-btn`, `.search-input`, `.goal-input`, `.close-btn`, and `.post-item` elements to support keyboard navigation accessibility.
- **Preview Links & Keyboard Hints**:
  - Updated `.preview a` bottom border to use `color-mix(in srgb, var(--accent) 50%, transparent)` instead of `#ffffff20`.
  - Updated `kbd, .key-hint` border from `#30363d` to `#3d4652`.
- **Scrollbar Thumbs**: Updated `::-webkit-scrollbar-thumb` background from `#1e242e` to `#343d4d` (hover: `#455062`) to ensure scrollbars are visible against dark backgrounds.

### 2. Visualizer Soft Borders (`.claude/skills/sssf/apps/visualizer/src/style.css`)
- Updated `--border-soft` variable from `#1a2231` to `#222b3d` to sharpen panel boundaries.

### 3. Automated Contrast Testing (`apps/inkwell/server.test.ts`)
- Added `style.css color variables meet WCAG AA contrast standards` test case.
- Fetches `/style.css` from the running test server and calculates WCAG relative luminance and contrast ratios.
- Asserts that `--text-faint` contrast ratio is ≥ 4.5:1 against `--bg` and `--bg-sidebar`.
- Asserts that `--text-dim` contrast ratio is ≥ 4.5:1 against `#11161e` and `#161b22`.
- Asserts that `--border` contrast ratio against `--bg` is ≥ 1.5:1.
- Verifies presence of `:focus-visible` rules in the stylesheet.

### 4. Implementation Specification (`specs/806adbfc_ui-visual-contrast.md`)
- Added implementation plan mapping out audit findings, contrast ratios, CSS variable updates, and verification steps.

## Affected Files

- `apps/inkwell/public/style.css`
- `apps/inkwell/server.test.ts`
- `.claude/skills/sssf/apps/visualizer/src/style.css`
- `specs/806adbfc_ui-visual-contrast.md`

## How to Verify

1. **Run Inkwell Test Suite**:
   ```bash
   bun test apps/inkwell/server.test.ts
   ```
   Ensures all API tests pass along with the new automated WCAG AA contrast assertions for `style.css`.

2. **Visual Inspection**:
   - Start the Inkwell server (`bun apps/inkwell/server.ts`).
   - Open the web application and verify that timestamps, placeholders, sidebar titles, buttons, and keyboard hints are clearly readable.
   - Use keyboard navigation (`Tab` / `Shift+Tab`) to verify visible focus outlines on interactive controls.

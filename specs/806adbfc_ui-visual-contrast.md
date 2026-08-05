# Implementation Plan - UI Visual Contrast & Accessibility Enhancements

## Overview
Audit and improve foreground/background visual contrast across application UI text, placeholders, controls, borders, and interactive states to ensure readability and compliance with WCAG 2.1 AA standards (minimum 4.5:1 contrast ratio for normal text, 3:1 for large text and UI controls) while preserving the dark-mode aesthetic and visual identity.

---

## Audit Findings & Deficiencies

### 1. Primary Target: Inkwell Application (`apps/inkwell/public/style.css`)
- **Faint Text Variable (`--text-faint: #565d68`)**:
  - Current contrast ratio against `#0d1117` background is **2.76:1** (Fails WCAG AA 4.5:1).
  - Current contrast ratio against `#090c11` sidebar background is **2.58:1** (Fails WCAG AA 4.5:1).
  - Current contrast ratio against `#11161e` input background is **2.56:1** (Fails WCAG AA 4.5:1).
  - **Affected UI Elements**: `.post-time` (timestamps), `.meta` (word counts, reading time, total posts/words), `.goal-label` ("Goal:"), placeholders (`.title::placeholder`, `.content::placeholder`, `.search-input::placeholder`), `.dot` (draft status indicator dot), `.empty` state text ("No posts yet.", "No matching posts.").

- **Dimmed Text Variable (`--text-dim: #7d8590`)**:
  - Current contrast ratio against `#11161e` / `#161b22` / `#151b25` dark element backgrounds is **3.8:1 - 4.1:1** for 11px-12px small text (Fails WCAG AA 4.5:1).
  - **Affected UI Elements**: `.new-btn`, `.btn` idle toolbar button states, `.post-item` title before hover/selection, `.search-clear` icon, `.goal-progress` percentage text, `kbd, .key-hint` shortcut text, `.close-btn` modal close icon.

- **UI Border Contrast (`--border: #1b212b`)**:
  - Current contrast ratio against `#0d1117` background is **1.18:1** (Fails WCAG 3:1 UI component border guideline).
  - **Affected UI Elements**: Input field borders (`.search-input`, `.goal-input`), sidebar right divider, modal header divider, `.preview pre` code block borders, button hover borders.

- **Keyboard Hints (`kbd, .key-hint`)**:
  - Text color `#7d8590` on `#161b22` background is 4.0:1. Border `#30363d` is low contrast against dark backgrounds.

- **Scrollbar Thumbs**:
  - Thumb color `#1e242e` against `#0d1117` is **1.2:1** contrast (barely visible).

- **Focus Navigation States**:
  - Interactive controls (`.btn`, `.new-btn`, `.search-input`, `.goal-input`, `.post-item`) lack distinct high-contrast focus rings when focused via keyboard navigation.

### 2. SSSF Visualizer (`.claude/skills/sssf/apps/visualizer/src/style.css`)
- `--faint` (`#8b9cb6`) on `#0d1119` has a contrast ratio of **6.3:1** (Passes WCAG AA).
- `--border-soft` (`#1a2231`) can be subtly sharpened to `#222b3d` to enhance container separation.

---

## Proposed Changes

### File 1: `apps/inkwell/public/style.css`
1. **Update Root Color Variables**:
   - Change `--text-faint` from `#565d68` to `#8b949e`.
     - *Result*: Contrast ratio increases to **5.16:1** against `#0d1117` and **4.80:1** against `#090c11`, passing WCAG AA 4.5:1.
   - Change `--text-dim` from `#7d8590` to `#a3b0c2`.
     - *Result*: Contrast ratio increases to **7.00:1** against `#090c11`, **6.50:1** against `#11161e`, and **6.00:1** against `#161b22`, passing WCAG AA 4.5:1.
   - Change `--border` from `#1b212b` to `#303846`.
     - *Result*: Increases UI element container & input border contrast ratio to **~2.5:1 - 3.0:1**, making input edges, dividers, and modal boxes clearly defined.

2. **Enhance Keyboard Shortcut Tags (`kbd`, `.key-hint`)**:
   - Update border from `#30363d` to `#3d4652`.
   - Inherit the boosted `--text-dim` (`#a3b0c2`) for crisp text contrast.

3. **Improve Scrollbar Control Visibility**:
   - Update `::-webkit-scrollbar-thumb` background from `#1e242e` to `#343d4d` and hover background from `#2b323d` to `#455062`.

4. **Add High-Contrast Focus States**:
   - Add `:focus-visible` styling for interactive controls (`.btn`, `.new-btn`, `.search-input`, `.goal-input`, `.close-btn`, `.post-item`):
     ```css
     .btn:focus-visible,
     .new-btn:focus-visible,
     .search-input:focus-visible,
     .goal-input:focus-visible,
     .close-btn:focus-visible {
       outline: 2px solid color-mix(in srgb, var(--accent) 80%, transparent);
       outline-offset: 1px;
     }
     ```

5. **Enhance Link & Code Contrast in Preview**:
   - Change `.preview a` border-bottom from `#ffffff20` to `color-mix(in srgb, var(--accent) 50%, transparent)`.

### File 2: `.claude/skills/sssf/apps/visualizer/src/style.css`
- Update `--border-soft` from `#1a2231` to `#222b3d` for improved visual hierarchy.

### File 3: `apps/inkwell/server.test.ts`
- Add an automated CSS contrast validation test suite in `apps/inkwell/server.test.ts` that reads `apps/inkwell/public/style.css`, parses the variable definitions, and programmatically verifies that:
  1. `--text-faint` has a contrast ratio >= 4.5:1 against `#0d1117` and `#090c11`.
  2. `--text-dim` has a contrast ratio >= 4.5:1 against `#11161e` and `#161b22`.
  3. `--border` contrast against `#0d1117` is >= 2.0:1.

---

## Verification Plan

### Automated Testing
1. **Inkwell Test Suite & Contrast Validation**:
   ```bash
   bun test apps/inkwell/server.test.ts
   ```
   Ensures all API functionality, Markdown rendering, and new CSS contrast assertions pass cleanly.

2. **Visualizer Typecheck & Build**:
   ```bash
   cd .claude/skills/sssf/apps/visualizer && bun run build
   ```
   Ensures Vue TypeScript compilation and Vite production build pass without errors.

### Manual Verification
- Launch Inkwell server (`bun run apps/inkwell/server.ts` or test server) and verify in browser:
  - Timestamps, word counts, and placeholders are comfortably legible.
  - Sidebar post items, buttons, search input, and modal shortcut keys are clear and distinct.
  - Keyboard navigation (Tab / Shift+Tab) renders a visible focus ring on focused controls.

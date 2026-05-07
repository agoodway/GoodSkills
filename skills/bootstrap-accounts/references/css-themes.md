# CSS Themes & Root Layout

## app.css

Replace the contents of `assets/css/app.css` with:

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/my_app_web";

@plugin "../vendor/heroicons";

@plugin "../vendor/daisyui" {
  themes: false;
}

/* Dark theme — deep navy with amber accents */
@plugin "../vendor/daisyui-theme" {
  name: "dark";
  default: false;
  prefersdark: true;
  color-scheme: "dark";
  --color-base-100: oklch(22% 0.02 260);
  --color-base-200: oklch(18% 0.018 260);
  --color-base-300: oklch(15% 0.015 260);
  --color-base-content: oklch(93% 0.01 260);
  --color-primary: oklch(78% 0.16 75);
  --color-primary-content: oklch(18% 0.04 75);
  --color-secondary: oklch(65% 0.06 260);
  --color-secondary-content: oklch(95% 0.01 260);
  --color-accent: oklch(72% 0.19 55);
  --color-accent-content: oklch(18% 0.04 55);
  --color-neutral: oklch(30% 0.025 260);
  --color-neutral-content: oklch(88% 0.01 260);
  --color-info: oklch(68% 0.14 240);
  --color-info-content: oklch(18% 0.03 240);
  --color-success: oklch(72% 0.17 155);
  --color-success-content: oklch(18% 0.04 155);
  --color-warning: oklch(80% 0.16 75);
  --color-warning-content: oklch(18% 0.04 75);
  --color-error: oklch(65% 0.22 25);
  --color-error-content: oklch(95% 0.02 25);
  --radius-selector: 0.375rem;
  --radius-field: 0.375rem;
  --radius-box: 0.625rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 1;
  --noise: 0;
}

/* Light theme — warm gray with amber primary */
@plugin "../vendor/daisyui-theme" {
  name: "light";
  default: true;
  prefersdark: false;
  color-scheme: "light";
  --color-base-100: oklch(99% 0.002 270);
  --color-base-200: oklch(96.5% 0.004 270);
  --color-base-300: oklch(92% 0.006 270);
  --color-base-content: oklch(25% 0.015 270);
  --color-primary: oklch(68% 0.17 55);
  --color-primary-content: oklch(99% 0.01 55);
  --color-secondary: oklch(50% 0.04 270);
  --color-secondary-content: oklch(98% 0.005 270);
  --color-accent: oklch(25% 0.02 270);
  --color-accent-content: oklch(98% 0.005 270);
  --color-neutral: oklch(40% 0.02 270);
  --color-neutral-content: oklch(98% 0 0);
  --color-info: oklch(62% 0.17 250);
  --color-info-content: oklch(97% 0.01 250);
  --color-success: oklch(65% 0.17 155);
  --color-success-content: oklch(98% 0.02 155);
  --color-warning: oklch(78% 0.16 75);
  --color-warning-content: oklch(25% 0.04 75);
  --color-error: oklch(58% 0.22 25);
  --color-error-content: oklch(97% 0.02 25);
  --radius-selector: 0.375rem;
  --radius-field: 0.375rem;
  --radius-box: 0.625rem;
  --size-selector: 0.25rem;
  --size-field: 0.25rem;
  --border: 1px;
  --depth: 1;
  --noise: 0;
}

/* LiveView variants */
@custom-variant phx-click-loading (.phx-click-loading&, .phx-click-loading &);
@custom-variant phx-submit-loading (.phx-submit-loading&, .phx-submit-loading &);
@custom-variant phx-change-loading (.phx-change-loading&, .phx-change-loading &);

/* DaisyUI dark mode via data attribute */
@custom-variant dark (&:where([data-theme=dark], [data-theme=dark] *));

/* Make LiveView wrapper divs transparent for layout */
[data-phx-session], [data-phx-teleported-src] { display: contents }

/* Sidebar dark panel — always dark regardless of theme */
.sidebar-panel {
  background: oklch(18% 0.02 260);
  color: oklch(88% 0.01 260);
}

[data-theme="light"] .sidebar-panel {
  background: oklch(20% 0.02 260);
  color: oklch(88% 0.01 260);
}

/* Responsive Table → Card Layout (mobile <md becomes stacked cards) */
.responsive-table { overflow-x: auto; }

.responsive-table thead th {
  font-size: 0.6875rem; font-weight: 700; text-transform: uppercase;
  letter-spacing: 0.06em; color: var(--color-base-content); opacity: 0.4;
  padding: 0.625rem 1.25rem; border-bottom: 1px solid var(--color-base-300);
}

.responsive-table tbody tr { transition: background-color 0.15s ease; }
.responsive-table tbody tr:hover { background-color: var(--color-base-200); }

.responsive-table tbody td {
  padding: 0.75rem 1.25rem;
  border-bottom: 1px solid color-mix(in oklch, var(--color-base-300) 40%, transparent);
  vertical-align: middle;
}

.responsive-table tbody tr:last-child td { border-bottom: none; }
.responsive-table .table-actions { width: 0; white-space: nowrap; font-weight: 600; }

@media (max-width: 767px) {
  .responsive-table { overflow-x: visible; }
  .responsive-table thead {
    position: absolute; width: 1px; height: 1px; overflow: hidden;
    clip: rect(0 0 0 0); white-space: nowrap;
  }
  .responsive-table table, .responsive-table tbody,
  .responsive-table tr, .responsive-table td { display: block; width: 100%; }
  .responsive-table tbody tr {
    margin-bottom: 0.625rem; border-radius: 0.625rem;
    border: 1px solid var(--color-base-300); overflow: hidden;
    background: var(--color-base-100);
  }
  .responsive-table tbody tr:hover { background-color: var(--color-base-100); }
  .responsive-table tbody td {
    display: flex; align-items: center; justify-content: space-between;
    gap: 0.75rem; padding: 0.5rem 0.875rem;
    border-bottom: 1px solid var(--color-base-200);
  }
  .responsive-table tbody td:last-child { border-bottom: none; }
  .responsive-table tbody td[data-label]::before {
    content: attr(data-label); font-size: 0.6875rem; font-weight: 700;
    text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--color-base-content); opacity: 0.4; flex-shrink: 0;
  }
  .responsive-table tbody td[data-label=""]::before { display: none; }
  .responsive-table .table-actions {
    width: 100%; justify-content: flex-end;
    background: var(--color-base-200); padding: 0.5rem 0.875rem;
  }
  .responsive-table .table-actions::before { display: none; }
}
```

## Root Layout

Update `lib/my_app_web/components/layouts/root.html.heex` with theme initialization script:

```heex
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <meta name="csrf-token" content={get_csrf_token()} />
    <.live_title default="MyApp" suffix=" · MyApp">
      {assigns[:page_title]}
    </.live_title>
    <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/js/app.js"}>
    </script>
    <script>
      (() => {
        const setTheme = (theme) => {
          if (theme === "system") {
            localStorage.removeItem("phx:theme");
            document.documentElement.removeAttribute("data-theme");
          } else {
            localStorage.setItem("phx:theme", theme);
            document.documentElement.setAttribute("data-theme", theme);
          }
        };
        if (!document.documentElement.hasAttribute("data-theme")) {
          setTheme(localStorage.getItem("phx:theme") || "system");
        }
        window.addEventListener("storage", (e) => e.key === "phx:theme" && setTheme(e.newValue || "system"));
        window.addEventListener("phx:set-theme", (e) => setTheme(e.target.dataset.phxTheme));
      })();
    </script>
  </head>
  <body>
    {@inner_content}
  </body>
</html>
```

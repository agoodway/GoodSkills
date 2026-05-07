---
name: bootstrap-astro
description: "Bootstrap Astro Site"
---

# Bootstrap Astro Site

Bootstrap a new Astro site in this directory with:
- Astro v5 with TypeScript (strict mode)
- Tailwind CSS v4 via Vite plugin
- React integration
- Sitemap integration
- Tidewave for AI agent integration (dev only)
- Partytown for Google Analytics
- Production-ready Kamal deployment config
- Nginx for static file serving

## Phase 1: Create Astro Project

### 1.1 Initialize Astro in Current Directory

Use bun to create the Astro project:

```bash
bun create astro@latest . --template minimal --typescript strict --git --install
```

When prompted:
- Template: `minimal`
- TypeScript: `strict`
- Install dependencies: `yes`
- Initialize git: `yes`

### 1.2 Install Core Dependencies

```bash
bun add @astrojs/react @astrojs/sitemap @astrojs/partytown
bun add react react-dom
bun add tailwindcss @tailwindcss/vite
bun add --dev tidewave
```

## Phase 2: Configure Tailwind CSS v4

### 2.1 Update Astro Config

**File:** `astro.config.mjs`

```javascript
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import partytown from '@astrojs/partytown';
import tailwindcss from '@tailwindcss/vite';
import tidewave from 'tidewave/vite-plugin';

export default defineConfig({
  site: 'https://your-domain.com', // UPDATE THIS

  integrations: [
    react(),
    sitemap(),
    partytown({
      config: {
        forward: ['dataLayer.push'], // Required for Google Analytics
      },
    }),
  ],

  vite: {
    plugins: [
      tailwindcss(),
      tidewave(), // AI agent integration (dev only)
    ],
  },
});
```

### 2.2 Create Global CSS

**File:** `src/styles/global.css`

```css
@import "tailwindcss";

/* Custom base styles */
@layer base {
  html {
    @apply antialiased;
  }

  body {
    @apply min-h-screen bg-white text-gray-900;
  }
}

/* Custom component styles */
@layer components {
  .btn {
    @apply px-4 py-2 rounded-lg font-medium transition-colors;
  }

  .btn-primary {
    @apply bg-blue-600 text-white hover:bg-blue-700;
  }
}
```

### 2.3 Create Base Layout

**File:** `src/layouts/Layout.astro`

```astro
---
import '../styles/global.css';
import GoogleAnalytics from '../components/GoogleAnalytics.astro';

interface Props {
  title: string;
  description?: string;
}

const { title, description = 'Default description for your site' } = Astro.props;
---

<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content={description} />
    <link rel="icon" type="image/svg+xml" href="/favicon.svg" />
    <title>{title}</title>
    <GoogleAnalytics />
  </head>
  <body>
    <slot />
  </body>
</html>
```

## Phase 3: Google Analytics Setup

**File:** `src/components/GoogleAnalytics.astro`

```astro
---
// Google Analytics component using Partytown for performance optimization
// Only loads in production to prevent development traffic from skewing analytics
const GA_MEASUREMENT_ID = 'G-XXXXXXXXXX'; // Replace with your GA4 Measurement ID
---

{import.meta.env.PROD && (
  <>
    <!-- Google tag (gtag.js) with Partytown -->
    <script
      is:inline
      type="text/partytown"
      src={`https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`}
    ></script>
    <script is:inline type="text/partytown" define:vars={{ GA_MEASUREMENT_ID }}>
      window.dataLayer = window.dataLayer || [];
      function gtag() {
        dataLayer.push(arguments);
      }
      gtag('js', new Date());
      gtag('config', GA_MEASUREMENT_ID);
    </script>
  </>
)}
```

## Phase 4: Production Configuration

### 4.1 Create Production Astro Config

**File:** `astro.config.node.mjs`

```javascript
import { defineConfig } from 'astro/config';
import react from '@astrojs/react';
import sitemap from '@astrojs/sitemap';
import partytown from '@astrojs/partytown';
import tailwindcss from '@tailwindcss/vite';

export default defineConfig({
  site: 'https://your-domain.com', // UPDATE THIS

  // CRITICAL: Always use trailing slashes to prevent nginx port leakage
  trailingSlash: 'always',

  integrations: [
    react(),
    sitemap(),
    partytown({
      config: {
        forward: ['dataLayer.push'],
      },
    }),
  ],

  vite: {
    plugins: [tailwindcss()],
  },
});
```

### 4.2 Update Package Scripts

**File:** `package.json` (scripts section)

```json
{
  "scripts": {
    "dev": "astro dev",
    "build": "astro check && astro build",
    "preview": "astro preview",
    "check": "astro check"
  }
}
```

## Phase 5: Kamal Deployment Setup

### 5.1 Create Kamal Config

**File:** `config/deploy.yml`

```yaml
# Kamal deployment configuration
service: your-app-name  # UPDATE THIS

# Docker image name - update with your GitHub username
image: ghcr.io/your-username/your-app-name  # UPDATE THIS

# Production servers
servers:
  web:
    - 123.456.789.012  # UPDATE with your server IP

# GitHub Container Registry configuration
registry:
  server: ghcr.io
  username: your-github-username  # UPDATE THIS
  password:
    - GITHUB_TOKEN

# Build configuration
builder:
  arch: amd64

# Environment variables
env:
  clear:
    NODE_ENV: production

# Kamal proxy configuration with SSL
proxy:
  host: your-domain.com  # UPDATE THIS
  app_port: 3022
  ssl: true
  healthcheck:
    path: /health
    interval: 3
    timeout: 3

# SSH configuration
ssh:
  user: root
  keys: ["~/.ssh/id_rsa"]

# Retain last 5 deployed containers for quick rollbacks
retain_containers: 5

# Logging
logging:
  driver: json-file
  options:
    max-size: "10m"
    max-file: "3"
```

### 5.2 Create Dockerfile

**File:** `Dockerfile`

```dockerfile
# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Install git (required by npm for some dependencies)
RUN apk add --no-cache git

# Copy package files
COPY package.json bun.lock* package-lock.json* ./

# Install dependencies
RUN npm install || bun install

# Copy source code
COPY . .

# Build the application using Docker-specific config
RUN npm run build -- --config astro.config.node.mjs

# Runtime stage - use nginx to serve static files
FROM nginx:alpine

# Install curl for healthcheck
RUN apk add --no-cache curl

# Copy built static files from builder
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy custom nginx server configuration
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Expose port 3022
EXPOSE 3022

# Start nginx
CMD ["nginx", "-g", "daemon off;"]
```

### 5.3 Create Nginx Config

**File:** `nginx.conf`

```nginx
server {
    listen 3022;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    # Trust X-Forwarded headers from Kamal proxy
    real_ip_header X-Forwarded-For;
    set_real_ip_from 0.0.0.0/0;

    # CRITICAL: Prevent port from appearing in redirects
    port_in_redirect off;
    absolute_redirect off;

    # Gzip compression for better performance
    gzip on;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    gzip_vary on;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }

    # Handle client-side routing and static files
    location / {
        try_files $uri $uri/ $uri.html /index.html;
    }

    # Optimize static asset caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    # Ensure proper handling of HTML files (no caching)
    location ~* \.html$ {
        expires -1;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }

    # Handle sitemap
    location = /sitemap-index.xml {
        add_header Content-Type application/xml;
    }

    location = /sitemap-0.xml {
        add_header Content-Type application/xml;
    }
}
```

### 5.4 Create .dockerignore

**File:** `.dockerignore`

```
node_modules
.git
.gitignore
.env
.env.*
dist
.astro
*.md
.vscode
.idea
.DS_Store
```

### 5.5 Create Environment Example

**File:** `.env.example`

```bash
# GitHub Container Registry Token
# Create at: https://github.com/settings/tokens
# Required scopes: write:packages, read:packages, delete:packages
GITHUB_TOKEN=ghp_your_github_personal_access_token_here
```

## Phase 6: Create Initial Page

**File:** `src/pages/index.astro`

```astro
---
import Layout from '../layouts/Layout.astro';
---

<Layout title="Welcome" description="Your site description here">
  <main class="min-h-screen flex items-center justify-center">
    <div class="text-center">
      <h1 class="text-4xl font-bold text-gray-900 mb-4">
        Welcome to Your Site
      </h1>
      <p class="text-lg text-gray-600 mb-8">
        Built with Astro, Tailwind CSS, and ready for deployment.
      </p>
      <a href="#" class="btn btn-primary">
        Get Started
      </a>
    </div>
  </main>
</Layout>
```

## Checklist

After running this command, you should have:

- [ ] Astro project initialized with TypeScript
- [ ] All dependencies installed
- [ ] Tailwind CSS v4 configured
- [ ] React integration set up
- [ ] Tidewave for AI agent support (dev only)
- [ ] Google Analytics with Partytown
- [ ] Kamal deployment configuration
- [ ] Nginx configuration
- [ ] Docker setup for production

## Placeholder Values to Update

Search and replace these values in your project:

| Placeholder | Description | Example |
|-------------|-------------|---------|
| `your-domain.com` | Your production domain | `example.com` |
| `your-app-name` | Service/app name | `my-awesome-app` |
| `your-username` | GitHub username | `johndoe` |
| `your-github-username` | GitHub username | `johndoe` |
| `123.456.789.012` | Server IP address | `165.232.128.50` |
| `G-XXXXXXXXXX` | GA4 Measurement ID | `G-ABC123DEF4` |

## Development Commands

```bash
# Start dev server
bun dev

# Build for production
bun run build

# Preview production build
bun run preview

# Type check
bunx astro check
```

## Deployment Commands

```bash
# Install Kamal (one-time)
gem install kamal

# First-time deployment
kamal setup

# Subsequent deployments
kamal deploy

# View logs
kamal app logs -f

# Rollback
kamal rollback [VERSION]
```

---

**Note:** This command sets up a complete Astro project structure. After running, update all placeholder values and configure your domain, server IPs, and Google Analytics ID.

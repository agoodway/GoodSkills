---
name: bootstrap-astro-ses
description: "Bootstrap Astro site with AWS SES form handling"
---


# Bootstrap Astro with AWS SES Form Handling

Set up an Astro project with SSR and AWS SES email integration for contact forms.

## Prerequisites Check

Before proceeding, verify:
- Astro project exists with SSR adapter (`@astrojs/vercel`, `@astrojs/node`, etc.)
- If no Astro project exists, create one first with `pnpm create astro@latest`

## Phase 1: Install Dependencies

```bash
pnpm add @aws-sdk/client-ses zod
```

## Phase 2: Environment Configuration

### Create `.env` file

```env
# AWS Credentials
AWS_ACCESS_KEY_ID=your-access-key-id
AWS_SECRET_ACCESS_KEY=your-secret-access-key
AWS_REGION=us-east-2

# Email Configuration
FROM_EMAIL=noreply@yourdomain.com
CONTACT_EMAIL_TO=your-email@yourdomain.com

# Development Only
DISABLE_EMAIL=true
```

### Create `.env.example` (for version control)

```env
# AWS Credentials
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_REGION=us-east-2

# Email Configuration
FROM_EMAIL=noreply@yourdomain.com
CONTACT_EMAIL_TO=

# Development Only
DISABLE_EMAIL=true
```

### Update `.gitignore`

Add:
```
.env
.env.local
!.env.example
```

## Phase 3: Create Email Utility

**File:** `src/lib/email.ts`

```typescript
import { SESClient, SendEmailCommand } from '@aws-sdk/client-ses';
import type { SendEmailCommandInput } from '@aws-sdk/client-ses';

const getEnvVar = (key: string): string | undefined => {
  return import.meta.env?.[key] || process.env[key];
};

export async function createSESClient(): Promise<SESClient | null> {
  try {
    if (getEnvVar('DISABLE_EMAIL') === 'true') {
      console.log('Email sending is disabled via DISABLE_EMAIL environment variable');
      return null;
    }

    const accessKeyId = getEnvVar('AWS_ACCESS_KEY_ID');
    const secretAccessKey = getEnvVar('AWS_SECRET_ACCESS_KEY');
    const region = getEnvVar('AWS_REGION') || 'us-east-2';

    if (!accessKeyId || !secretAccessKey) {
      console.warn('AWS credentials not found. Email sending will be disabled.');
      return null;
    }

    return new SESClient({
      region,
      credentials: { accessKeyId, secretAccessKey },
    });
  } catch (error: any) {
    console.error('Failed to create SES client:', error.message);
    return null;
  }
}

export async function sendEmail(
  sesClient: SESClient,
  options: {
    to: string | string[];
    from: string;
    subject: string;
    html: string;
    text: string;
    replyTo?: string;
  }
): Promise<boolean> {
  try {
    const params: SendEmailCommandInput = {
      Source: options.from,
      Destination: {
        ToAddresses: Array.isArray(options.to) ? options.to : [options.to],
      },
      Message: {
        Subject: { Data: options.subject, Charset: 'UTF-8' },
        Body: {
          Html: { Data: options.html, Charset: 'UTF-8' },
          Text: { Data: options.text, Charset: 'UTF-8' },
        },
      },
      ReplyToAddresses: options.replyTo ? [options.replyTo] : undefined,
    };

    await sesClient.send(new SendEmailCommand(params));
    return true;
  } catch (error: any) {
    console.error('Failed to send email:', error.message);
    return false;
  }
}
```

## Phase 4: Create Validation Schema

**File:** `src/shared/schema.ts`

```typescript
import { z } from 'zod';

export const contactFormSchema = z.object({
  firstName: z.string().min(1, 'First name is required'),
  lastName: z.string().min(1, 'Last name is required'),
  email: z.string().email('Invalid email address'),
  company: z.string().optional(),
  message: z.string().min(1, 'Message is required'),
});

export type ContactFormData = z.infer<typeof contactFormSchema>;
```

## Phase 5: Create API Endpoint

**File:** `src/pages/api/contact.ts`

```typescript
import type { APIRoute } from 'astro';
import { z } from 'zod';
import { createSESClient, sendEmail } from '@/lib/email';
import { contactFormSchema } from '@/shared/schema';
import type { SESClient } from '@aws-sdk/client-ses';

export const prerender = false;

let sesClient: SESClient | null = null;

const getEnvVar = (key: string): string | undefined => {
  return import.meta.env?.[key] || process.env[key];
};

function formatEmailHtml(data: {
  firstName: string;
  lastName: string;
  email: string;
  company?: string;
  message: string;
}): string {
  return `
    <!DOCTYPE html>
    <html>
    <head><meta charset="utf-8"></head>
    <body style="font-family: sans-serif; max-width: 600px; margin: 0 auto;">
      <h1 style="color: #333;">New Contact Form Submission</h1>
      <table style="width: 100%; border-collapse: collapse;">
        <tr>
          <td style="padding: 8px; color: #666;"><strong>Name:</strong></td>
          <td style="padding: 8px;">${data.firstName} ${data.lastName}</td>
        </tr>
        <tr>
          <td style="padding: 8px; color: #666;"><strong>Email:</strong></td>
          <td style="padding: 8px;"><a href="mailto:${data.email}">${data.email}</a></td>
        </tr>
        <tr>
          <td style="padding: 8px; color: #666;"><strong>Company:</strong></td>
          <td style="padding: 8px;">${data.company || 'Not provided'}</td>
        </tr>
      </table>
      <h2 style="color: #333;">Message</h2>
      <p style="color: #444; line-height: 1.6;">${data.message}</p>
    </body>
    </html>
  `;
}

function formatEmailText(data: {
  firstName: string;
  lastName: string;
  email: string;
  company?: string;
  message: string;
}): string {
  return `
New Contact Form Submission

Name: ${data.firstName} ${data.lastName}
Email: ${data.email}
Company: ${data.company || 'Not provided'}

Message:
${data.message}
  `.trim();
}

export const POST: APIRoute = async ({ request }) => {
  try {
    const body = await request.json();
    const validatedData = contactFormSchema.parse(body);

    if (!sesClient) {
      sesClient = await createSESClient();
    }

    let emailSent = false;

    if (sesClient) {
      const toEmail = getEnvVar('CONTACT_EMAIL_TO') || 'your-email@example.com';
      const fromEmail = getEnvVar('FROM_EMAIL') || 'noreply@example.com';

      emailSent = await sendEmail(sesClient, {
        to: toEmail,
        from: fromEmail,
        subject: `New Contact: ${validatedData.firstName} ${validatedData.lastName}`,
        html: formatEmailHtml(validatedData),
        text: formatEmailText(validatedData),
        replyTo: validatedData.email,
      });
    }

    return new Response(
      JSON.stringify({ success: true, emailSent }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    if (error instanceof z.ZodError) {
      return new Response(
        JSON.stringify({ success: false, error: 'Validation failed', details: error.errors }),
        { status: 400, headers: { 'Content-Type': 'application/json' } }
      );
    }

    console.error('API error:', error);
    return new Response(
      JSON.stringify({ success: false, error: 'Internal server error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }
};
```

## Phase 6: Create React Form Component

**File:** `src/components/ContactForm.tsx`

```tsx
import { useState } from 'react';
import { z } from 'zod';

const formSchema = z.object({
  firstName: z.string().min(1, 'First name is required'),
  lastName: z.string().min(1, 'Last name is required'),
  email: z.string().email('Invalid email address'),
  company: z.string().optional(),
  message: z.string().min(1, 'Message is required'),
});

type FormData = z.infer<typeof formSchema>;

export default function ContactForm() {
  const [formData, setFormData] = useState<FormData>({
    firstName: '',
    lastName: '',
    email: '',
    company: '',
    message: '',
  });
  const [errors, setErrors] = useState<Record<string, string>>({});
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitStatus, setSubmitStatus] = useState<'idle' | 'success' | 'error'>('idle');

  const handleChange = (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) => {
    const { name, value } = e.target;
    setFormData((prev) => ({ ...prev, [name]: value }));
    if (errors[name]) {
      setErrors((prev) => ({ ...prev, [name]: '' }));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    setErrors({});

    const result = formSchema.safeParse(formData);
    if (!result.success) {
      const fieldErrors: Record<string, string> = {};
      result.error.errors.forEach((err) => {
        if (err.path[0]) {
          fieldErrors[err.path[0] as string] = err.message;
        }
      });
      setErrors(fieldErrors);
      setIsSubmitting(false);
      return;
    }

    try {
      const response = await fetch('/api/contact', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(formData),
      });

      const data = await response.json();

      if (data.success) {
        setSubmitStatus('success');
        setFormData({ firstName: '', lastName: '', email: '', company: '', message: '' });
      } else {
        setSubmitStatus('error');
        if (data.details) {
          const fieldErrors: Record<string, string> = {};
          data.details.forEach((err: any) => {
            if (err.path[0]) {
              fieldErrors[err.path[0]] = err.message;
            }
          });
          setErrors(fieldErrors);
        }
      }
    } catch {
      setSubmitStatus('error');
    } finally {
      setIsSubmitting(false);
    }
  };

  if (submitStatus === 'success') {
    return (
      <div className="success-message">
        <h3>Thank you!</h3>
        <p>We've received your message and will get back to you soon.</p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit}>
      <div>
        <label htmlFor="firstName">First Name *</label>
        <input type="text" id="firstName" name="firstName" value={formData.firstName} onChange={handleChange} />
        {errors.firstName && <span className="error">{errors.firstName}</span>}
      </div>

      <div>
        <label htmlFor="lastName">Last Name *</label>
        <input type="text" id="lastName" name="lastName" value={formData.lastName} onChange={handleChange} />
        {errors.lastName && <span className="error">{errors.lastName}</span>}
      </div>

      <div>
        <label htmlFor="email">Email *</label>
        <input type="email" id="email" name="email" value={formData.email} onChange={handleChange} />
        {errors.email && <span className="error">{errors.email}</span>}
      </div>

      <div>
        <label htmlFor="company">Company</label>
        <input type="text" id="company" name="company" value={formData.company} onChange={handleChange} />
      </div>

      <div>
        <label htmlFor="message">Message *</label>
        <textarea id="message" name="message" value={formData.message} onChange={handleChange} rows={5} />
        {errors.message && <span className="error">{errors.message}</span>}
      </div>

      {submitStatus === 'error' && <div className="error-message">Something went wrong. Please try again.</div>}

      <button type="submit" disabled={isSubmitting}>
        {isSubmitting ? 'Sending...' : 'Send Message'}
      </button>
    </form>
  );
}
```

## Phase 7: Create Contact Page

**File:** `src/pages/contact.astro`

```astro
---
import Layout from '@/layouts/Layout.astro';
import ContactForm from '@/components/ContactForm';
---

<Layout title="Contact Us">
  <main>
    <h1>Contact Us</h1>
    <ContactForm client:load />
  </main>
</Layout>
```

## Phase 8: Update TypeScript Config

**File:** `tsconfig.json`

Ensure path aliases are configured:

```json
{
  "compilerOptions": {
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"],
      "@shared/*": ["src/shared/*"]
    }
  }
}
```

## Verification Checklist

After setup, verify:
- [ ] Dependencies installed (`@aws-sdk/client-ses`, `zod`)
- [ ] Environment variables configured in `.env`
- [ ] `.env.example` created for reference
- [ ] `src/lib/email.ts` created
- [ ] `src/shared/schema.ts` created
- [ ] `src/pages/api/contact.ts` created
- [ ] `src/components/ContactForm.tsx` created
- [ ] `src/pages/contact.astro` created
- [ ] TypeScript path aliases configured

## File Structure

```
src/
├── lib/
│   └── email.ts              # SES client and email utilities
├── shared/
│   └── schema.ts             # Zod validation schemas
├── components/
│   └── ContactForm.tsx       # React form component
└── pages/
    ├── contact.astro         # Contact page
    └── api/
        └── contact.ts        # API endpoint
```

## AWS SES Setup Notes

1. **Create IAM User** with `AmazonSESFullAccess` policy
2. **Verify sender email** in AWS SES Console → Verified Identities
3. **Request production access** to send to unverified emails (SES sandbox mode limits recipients)

## Development Tips

- Set `DISABLE_EMAIL=true` in development to skip actual email sending
- Email content is logged to console when disabled
- Test form validation before enabling real email sending

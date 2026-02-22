---
name: authentication
description: This skill should be used when the user is building or reviewing login flows, magic links, SSO (SAML/OIDC), multi-factor authentication (MFA), OTP input fields, password reset, or session management. Covers the modern auth stack hierarchy, MFA fatigue prevention, session expiry UX, and GDPR compliance for authentication.
version: 1.0.0
---

# Authentication Should Be Invisible

10% of active SaaS users get stuck in password reset flows monthly, and 75% of those quit. That is a potential 7.5% monthly user base loss from authentication friction alone.

## The Modern Auth Stack

Support three methods, in order of preference:

### 1. Magic Links (Frictionless Default)
The lowest-friction option. Airtable found 94% of enterprise users preferred them. Send a one-time link to the user's email — no password to remember.

### 2. SSO via SAML/OIDC (Enterprise)
Non-negotiable for enterprise customers and SOC 2 compliance. Integrate with identity providers like Okta, Azure AD, Google Workspace.

### 3. Password + MFA (Fallback)
For high-security contexts or users who prefer passwords. Always pair with multi-factor authentication.

## MFA UX Details

The implementation details matter enormously:

**OTP input fields:**
- Use `input type="text" inputmode="numeric"` — NOT `type="number"` (which allows scroll-wheel changes and scientific notation)
- Set `autocomplete="one-time-code"` for iOS/macOS autofill
- **Auto-submit** the form once the user enters a valid-length code

**Preventing MFA fatigue:**
- Use number matching (display a number, user confirms in their authenticator app) rather than simple approve/deny push notifications
- Verizon's DBIR shows MFA fatigue prompt-bombing succeeds at 3.5x the rate of technical MFA bypasses
- Apply adaptive MFA: stronger verification on untrusted devices, unexpected geolocations, or unusual hours

## Session Management

- Warn before expiration with a **modal countdown timer** offering "Continue Session" and "Log Out" options
- After auto-logout, show an **inline notification on the login page** explaining what happened
- Most critically: clearly communicate **what was saved and what was lost**

## Password Reset

Never let the reset flow become a dead end:
- Confirmation page should be clear and immediate
- Include a "Resend" option
- Show estimated delivery time for the reset email
- After reset, redirect to login with a success message

## GDPR Compliance

For applications accessible to EU citizens:
- Provide a self-service data export/deletion portal
- Respond to data subject requests within 30 days
- Implement audit logs capturing who accessed what data, when, from where, and why

## Examples

Working implementations in `examples/`:
- **`examples/otp-input.md`** — OTP digit input with correct HTML attributes, auto-advance, paste support, and auto-submit in React and Vue
- **`examples/session-expiry-modal.md`** — Countdown warning modal with session extension and post-logout notification

## Review Checklist

When reviewing or building authentication:

- [ ] Magic links supported as the primary, frictionless auth method
- [ ] SSO via SAML/OIDC available for enterprise customers
- [ ] Password + MFA available as fallback
- [ ] OTP fields use `type="text" inputmode="numeric"`, not `type="number"`
- [ ] OTP fields have `autocomplete="one-time-code"`
- [ ] OTP auto-submits on valid-length entry
- [ ] MFA uses number matching, not simple approve/deny
- [ ] Adaptive MFA applied for untrusted devices/locations
- [ ] Session expiry shows countdown modal with Continue/Log Out
- [ ] Post-logout login page explains what happened and what was saved
- [ ] Password reset flow has clear confirmation, resend option, and success redirect
- [ ] GDPR: self-service data export/deletion portal exists
- [ ] Audit logs capture access details

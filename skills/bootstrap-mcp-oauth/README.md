# Bootstrap MCP OAuth

Overlay OAuth 2.1 + PKCE on a Phoenix ExMCP 1.1 server. Account-scoped
resource URLs, RFC 9728 metadata, dynamic client registration, consent,
and token-resource binding — the goodviews MCP auth pattern.

Requires `/bootstrap-mcp` (Hex 1.1 HTTP stack), `/boruta bootstrap`
(OAuth provider), and `/bootstrap-accounts` (account slugs + membership).

## Install

```bash
npx skills add agoodway/GoodSkills --skill bootstrap-mcp-oauth -g
```

```bash
npx skills add agoodway/GoodSkills --skill bootstrap-mcp-oauth
```

## Usage

```
/bootstrap-mcp-oauth
```

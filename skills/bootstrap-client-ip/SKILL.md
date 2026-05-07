---
name: bootstrap-client-ip
description: >
  Bootstrap a ClientIP module in a Phoenix 1.8 app that extracts the real client IP address
  from proxy headers (X-Forwarded-For, X-Real-Ip, Fly-Client-IP, CF-Connecting-IP) with
  configurable trusted proxies. Creates the module, a plug for assigning client_ip to conn,
  and config entries. Use when the user says "bootstrap client ip", "add client ip",
  "setup remote ip", "get real ip", "client ip module", or wants to resolve client IPs
  behind proxies in a Phoenix app.
---

# Bootstrap Client IP

Add a `ClientIP` module to a Phoenix 1.8 app that resolves the real client IP address from reverse proxy headers, with configurable trusted proxy ranges and a conn-assigning plug.

## What Gets Created/Configured

1. **lib/<app>_web/client_ip.ex** — Core module that extracts real IP from proxy headers
2. **lib/<app>_web/plugs/client_ip.ex** — Plug that assigns `:client_ip` to conn
3. **config/config.exs** — Default trusted proxy config and header priority
4. **config/runtime.exs** — Production trusted proxy config via env var (optional)

## App Name Detection

Detect from `mix.exs`:
- **App module prefix** (e.g., `MyApp`) — the module namespace
- **OTP app name** (e.g., `:my_app`) — used in config atoms
- **Web module prefix** (e.g., `MyAppWeb`) — for web module references

Also detect:
- **Deployment target** — Check for `fly.toml` (Fly.io), `render.yaml` (Render), Dockerfile with cloud hints, or ask the user
- **Existing remote_ip config** — Check if `remote_ip` hex package is already in use
- **Router pipelines** — Identify the browser and API pipelines for plug placement

## Phase 0: Discovery

**CRITICAL: Audit the target app before making any changes.**

### Discovery Checklist

1. **Existing IP handling** — Search for `remote_ip`, `client_ip`, `x-forwarded-for` in the codebase
   - If `remote_ip` hex package is already a dependency: report and ask user if they want a custom module instead
   - If custom IP handling exists: report what exists and skip those parts

2. **Deployment target** — Check for:
   - `fly.toml` → Fly.io (uses `Fly-Client-IP` header)
   - `render.yaml` → Render
   - Cloudflare references → uses `CF-Connecting-IP` header
   - If unclear: ask the user where the app is deployed

3. **Router** — Find the browser and API pipelines to know where to add the plug

4. **Endpoint** — Check `lib/<app>_web/endpoint.ex` for existing IP-related plugs

5. **Existing config** — Check config files for any `:client_ip` or `:remote_ip` settings

### Discovery Report

Present findings to user. If IP handling is already configured, confirm and skip. Otherwise show what will be added/changed and confirm the deployment target.

## Phase 1: Core Module

### Step 1: ClientIP Module

Create `lib/<app>_web/client_ip.ex`:

```elixir
defmodule <WebModule>.ClientIP do
  @moduledoc """
  Resolves the real client IP address from reverse proxy headers.

  When your app runs behind a load balancer or reverse proxy (Fly.io, Cloudflare,
  Nginx, etc.), `conn.remote_ip` returns the proxy's IP, not the client's.
  This module inspects forwarding headers to extract the actual client IP.

  ## Configuration

      config :<otp_app>, <WebModule>.ClientIP,
        # Headers to check, in priority order (first match wins)
        headers: ["fly-client-ip", "cf-connecting-ip", "x-real-ip", "x-forwarded-for"],
        # Trusted proxy CIDR ranges — IPs in these ranges are skipped in X-Forwarded-For
        trusted_proxies: ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16"]

  ## Usage

      iex> <WebModule>.ClientIP.resolve(conn)
      {203, 0, 113, 1}

      iex> <WebModule>.ClientIP.resolve(conn) |> <WebModule>.ClientIP.to_string()
      "203.0.113.1"
  """

  @default_headers [
    "fly-client-ip",
    "cf-connecting-ip",
    "x-real-ip",
    "x-forwarded-for"
  ]

  @default_trusted_proxies [
    "127.0.0.0/8",
    "10.0.0.0/8",
    "172.16.0.0/12",
    "192.168.0.0/16",
    "::1/128",
    "fc00::/7"
  ]

  @doc """
  Resolves the real client IP from `conn`.

  Checks configured headers in priority order. For `x-forwarded-for`, walks the
  chain right-to-left and returns the first IP not in the trusted proxy ranges.
  Falls back to `conn.remote_ip` if no forwarding headers are present.

  Returns a tuple like `{127, 0, 0, 1}` or `{0, 0, 0, 0, 0, 0, 0, 1}`.
  """
  @spec resolve(Plug.Conn.t()) :: :inet.ip_address()
  def resolve(conn) do
    headers = config(:headers, @default_headers)

    Enum.find_value(headers, conn.remote_ip, fn header ->
      case Plug.Conn.get_req_header(conn, header) do
        [value | _] when value != "" -> parse_header(header, value)
        _ -> nil
      end
    end)
  end

  @doc """
  Converts an IP tuple to a human-readable string.

  ## Examples

      iex> <WebModule>.ClientIP.to_string({203, 0, 113, 1})
      "203.0.113.1"

      iex> <WebModule>.ClientIP.to_string({0, 0, 0, 0, 0, 0, 0, 1})
      "::1"
  """
  @spec to_string(:inet.ip_address()) :: String.t()
  def to_string(ip) do
    :inet.ntoa(ip) |> List.to_string()
  end

  # --- Private ---

  @spec parse_header(String.t(), String.t()) :: :inet.ip_address() | nil
  defp parse_header("x-forwarded-for", value) do
    trusted = trusted_cidrs()

    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reverse()
    |> Enum.find_value(fn raw_ip ->
      case parse_ip(raw_ip) do
        {:ok, ip} -> if not ip_in_cidrs?(ip, trusted), do: ip
        :error -> nil
      end
    end)
  end

  defp parse_header(_header, value) do
    value
    |> String.trim()
    |> parse_ip()
    |> case do
      {:ok, ip} -> ip
      :error -> nil
    end
  end

  @spec parse_ip(String.t()) :: {:ok, :inet.ip_address()} | :error
  defp parse_ip(ip_string) do
    ip_string
    |> String.to_charlist()
    |> :inet.parse_address()
  end

  @spec trusted_cidrs() :: [{:inet.ip_address(), non_neg_integer()}]
  defp trusted_cidrs do
    config(:trusted_proxies, @default_trusted_proxies)
    |> Enum.map(&parse_cidr/1)
    |> Enum.reject(&is_nil/1)
  end

  @spec parse_cidr(String.t()) :: {:inet.ip_address(), non_neg_integer()} | nil
  defp parse_cidr(cidr) do
    case String.split(cidr, "/") do
      [ip_str, mask_str] ->
        with {:ok, ip} <- parse_ip(ip_str),
             {mask, ""} <- Integer.parse(mask_str) do
          {ip, mask}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec ip_in_cidrs?(:inet.ip_address(), [{:inet.ip_address(), non_neg_integer()}]) :: boolean()
  defp ip_in_cidrs?(ip, cidrs) do
    Enum.any?(cidrs, fn {network, mask} -> ip_in_cidr?(ip, network, mask) end)
  end

  @spec ip_in_cidr?(:inet.ip_address(), :inet.ip_address(), non_neg_integer()) :: boolean()
  defp ip_in_cidr?(ip, network, mask) when tuple_size(ip) == tuple_size(network) do
    ip_bits = ip_to_integer(ip)
    net_bits = ip_to_integer(network)
    bit_size = tuple_size(ip) * 8
    shift = bit_size - mask
    Bitwise.bsr(ip_bits, shift) == Bitwise.bsr(net_bits, shift)
  end

  defp ip_in_cidr?(_ip, _network, _mask), do: false

  @spec ip_to_integer(:inet.ip_address()) :: non_neg_integer()
  defp ip_to_integer(ip) when tuple_size(ip) == 4 do
    ip |> Tuple.to_list() |> Enum.reduce(0, fn octet, acc -> Bitwise.bsl(acc, 8) + octet end)
  end

  defp ip_to_integer(ip) when tuple_size(ip) == 8 do
    ip |> Tuple.to_list() |> Enum.reduce(0, fn word, acc -> Bitwise.bsl(acc, 16) + word end)
  end

  @spec config(atom(), term()) :: term()
  defp config(key, default) do
    Application.get_env(:<otp_app>, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
```

**ADAPT header priority based on deployment target:**
- **Fly.io** — Put `"fly-client-ip"` first (most reliable, set by Fly's proxy)
- **Cloudflare** — Put `"cf-connecting-ip"` first
- **AWS ALB/ELB** — Use `"x-forwarded-for"` only
- **Nginx** — Put `"x-real-ip"` first if configured, otherwise `"x-forwarded-for"`
- **Generic/Unknown** — Use the default order shown above

## Phase 2: Plug

### Step 2: ClientIP Plug

Create `lib/<app>_web/plugs/client_ip.ex`:

```elixir
defmodule <WebModule>.Plugs.ClientIP do
  @moduledoc """
  Plug that resolves the real client IP and assigns it to the connection.

  Assigns both `:client_ip` (the IP tuple) and `:client_ip_string` (human-readable)
  to `conn.assigns`.

  ## Usage in Router

      pipeline :browser do
        # ... other plugs
        plug <WebModule>.Plugs.ClientIP
      end

  ## Accessing in Controllers/LiveViews

      conn.assigns.client_ip          # => {203, 0, 113, 1}
      conn.assigns.client_ip_string   # => "203.0.113.1"
  """

  @behaviour Plug

  alias <WebModule>.ClientIP

  @impl Plug
  @spec init(Keyword.t()) :: Keyword.t()
  def init(opts), do: opts

  @impl Plug
  @spec call(Plug.Conn.t(), Keyword.t()) :: Plug.Conn.t()
  def call(conn, _opts) do
    ip = ClientIP.resolve(conn)

    conn
    |> Plug.Conn.assign(:client_ip, ip)
    |> Plug.Conn.assign(:client_ip_string, ClientIP.to_string(ip))
  end
end
```

## Phase 3: Configuration

### Step 3: Base Config (config/config.exs)

Add if not present:

```elixir
# Client IP resolution — configure header priority and trusted proxies
config :<otp_app>, <WebModule>.ClientIP,
  headers: ["fly-client-ip", "cf-connecting-ip", "x-real-ip", "x-forwarded-for"],
  trusted_proxies: ["127.0.0.0/8", "10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "::1/128", "fc00::/7"]
```

**ADAPT `headers` list:** Reorder based on deployment target (see Phase 1 notes).

**ADAPT `trusted_proxies` list:** If deploying on:
- **Fly.io** — Add Fly's internal ranges if needed (usually not required since `fly-client-ip` bypasses the chain)
- **Cloudflare** — Optionally add Cloudflare's published IP ranges from https://www.cloudflare.com/ips/
- **AWS** — Add the VPC CIDR range

### Step 4: Runtime Config (config/runtime.exs) — Optional

Inside the `if config_env() == :prod do` block, add if the user wants runtime-configurable proxies:

```elixir
  # Client IP — additional trusted proxies for production (comma-separated CIDRs)
  if trusted = System.get_env("TRUSTED_PROXY_CIDRS") do
    existing = Application.get_env(:<otp_app>, <WebModule>.ClientIP, [])
    default_proxies = Keyword.get(existing, :trusted_proxies, [])
    extra_proxies = String.split(trusted, ",") |> Enum.map(&String.trim/1)

    config :<otp_app>, <WebModule>.ClientIP,
      Keyword.merge(existing, trusted_proxies: default_proxies ++ extra_proxies)
  end
```

**Important:** This step is optional. Only add if the user needs to configure trusted proxies at runtime. Place inside the existing `if config_env() == :prod do` block — do not create a duplicate conditional.

## Phase 4: Router Integration

### Step 5: Add Plug to Pipelines

In `lib/<app>_web/router.ex`, add the plug to the browser pipeline (and optionally API pipeline):

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {<WebModule>.Layouts, :root}
  plug :protect_from_forgery
  plug :put_secure_browser_headers
  plug <WebModule>.Plugs.ClientIP    # <-- Add this
end
```

**Placement:** Add after the standard Phoenix plugs but before auth plugs. The IP plug has no dependencies on session or auth state.

If the app also has an API pipeline, add there too:
```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug <WebModule>.Plugs.ClientIP    # <-- Add this
end
```

## Phase 5: Verification

1. Run `mix compile --warnings-as-errors` to verify everything compiles
2. Run `mix test` to ensure no regressions
3. Suggest the user write a quick test or verify in dev:

```elixir
# In any controller or LiveView:
Logger.info("Client IP: #{conn.assigns.client_ip_string}")
```

## Usage Examples

### In Controllers
```elixir
def create(conn, params) do
  Logger.info("Request from #{conn.assigns.client_ip_string}")
  # Use for rate limiting, geo-lookup, audit logging, etc.
end
```

### In LiveViews
```elixir
# Client IP is available via the conn in mount/3 (connected or disconnected)
def mount(_params, _session, socket) do
  # If you need the IP in LiveView, pass it through the session or use connect_info
  {:ok, socket}
end
```

### Direct Usage (without plug)
```elixir
alias <WebModule>.ClientIP

ip = ClientIP.resolve(conn)
ip_string = ClientIP.to_string(ip)
```

### For LiveView connect_info

If you need the client IP in LiveView after the WebSocket connects, configure `connect_info` in the endpoint:

```elixir
# In endpoint.ex
socket "/live", Phoenix.LiveView.Socket,
  websocket: [connect_info: [:peer_data, :x_headers]]
```

Then in the LiveView:
```elixir
def mount(_params, _session, socket) do
  ip =
    if connected?(socket) do
      get_connect_info(socket, :x_headers)
      |> Enum.find_value(fn
        {"x-forwarded-for", val} -> val |> String.split(",") |> List.first() |> String.trim()
        _ -> nil
      end)
    end

  {:ok, assign(socket, :client_ip, ip)}
end
```

## Notes

- `conn.remote_ip` only gives you the last hop — behind any proxy, that's the proxy's IP
- The module checks headers in priority order and returns the first valid result
- For `x-forwarded-for`, it walks right-to-left skipping trusted proxy IPs to prevent spoofing
- IPv6 addresses are fully supported
- No external dependencies required — uses only `:inet` from OTP and `Plug.Conn`
- The trusted proxy list defaults to RFC 1918 private ranges — suitable for most deployments
- For Fly.io, the `fly-client-ip` header is the most reliable since it's set by Fly's edge proxy and can't be spoofed by the client

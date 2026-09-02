# Dependency, application, router, endpoint, Transport

Replace `MyApp` / `my_app` / `MyAppWeb` with the detected names.

## mix.exs

```elixir
{:ex_mcp, "~> 1.1.1"},
```

Then `mix deps.get`.

Do not pin `github: "fire/ex-mcp"`. Hex 1.1.x is the supported transport.

## Endpoint parsers

`lib/my_app_web/endpoint.ex` — add `body_reader` to the existing `Plug.Parsers`
plug. Do not add a second parsers plug.

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library(),
  body_reader: {MyAppWeb.Plugs.CacheBody, :read_body, []}
```

`CacheBody` is in [http.md](http.md). It must concatenate every `{:more, chunk}`.

## Application supervisor

Do **not** start `MyApp.MCPServer`. Do **not** start `AuthSessions` or
`SSEHub`. Do **not** call `ExMCP.HttpPlug.start_link/1`. Session registry is
started by the `:ex_mcp` application. Handlers are temporary per request.

## Config

`config/config.exs`:

```elixir
config :my_app,
  mcp_allowed_hosts: ["localhost", "127.0.0.1", "::1", "[::1]"]

config :my_app, :mcp,
  protocol_mode: :legacy_only,
  legacy_http_sse: true,
  cors_enabled: true,
  validate_origin: true,
  body_limit: 1_000_000,
  allowed_origins: [
    "http://localhost:6274",
    "http://localhost:6277"
  ]

config :ex_mcp, protocol_mode: :legacy_only
```

Inspector's default origin is `http://localhost:6274`. Add other browser
origins the team actually uses. Missing `Origin` stays valid for CLI clients.

`config/dev.exs` / `config/runtime.exs` (prod): append the real public host to
`mcp_allowed_hosts`. Production origins are the HTTPS Inspector/app origins,
not `*`.

`config/test.exs` — ConnTest uses `www.example.com`:

```elixir
config :my_app,
  mcp_allowed_hosts: ["localhost", "127.0.0.1", "::1", "[::1]", "www.example.com"]

config :my_app, :mcp,
  protocol_mode: :legacy_only,
  legacy_http_sse: true,
  cors_enabled: true,
  validate_origin: true,
  body_limit: 1_000_000,
  allowed_origins: [
    "http://localhost:6274",
    "http://www.example.com"
  ]
```

## Transport

`lib/my_app/mcp/transport.ex`

```elixir
defmodule MyApp.MCP.Transport do
  @moduledoc """
  ExMCP 1.1.x HTTP Plug options for the MCP endpoint.
  """

  @server_info %{name: "my_app", version: "0.1.0"}

  @spec plug_opts() :: keyword()
  def plug_opts do
    mcp = mcp_config()

    [
      handler: MyApp.MCPServer,
      handler_opts: &handler_opts/1,
      server_info: @server_info,
      protocol_mode: Keyword.get(mcp, :protocol_mode, :legacy_only),
      legacy_http_sse: Keyword.get(mcp, :legacy_http_sse, true),
      cors_enabled: Keyword.get(mcp, :cors_enabled, true),
      validate_origin: Keyword.get(mcp, :validate_origin, true),
      allowed_origins: allowed_origins(),
      allowed_hosts: allowed_hosts(),
      body_limit: Keyword.get(mcp, :body_limit, 1_000_000),
      oauth_enabled: false,
      principal_id: &principal_id/1,
      tenant_id: &tenant_id/1
    ]
  end

  @spec handler_opts(Plug.Conn.t()) :: map()
  def handler_opts(%Plug.Conn{} = conn) do
    %{
      api_key: conn.assigns[:mcp_api_key],
      user: conn.assigns[:mcp_user],
      account: conn.assigns[:mcp_account],
      scopes: conn.assigns[:mcp_scopes] || []
    }
  end

  @spec principal_id(Plug.Conn.t()) :: String.t() | nil
  def principal_id(%Plug.Conn{} = conn) do
    cond do
      match?(%{id: id} when not is_nil(id), conn.assigns[:mcp_user]) ->
        to_string(conn.assigns.mcp_user.id)

      match?(%{id: id} when not is_nil(id), conn.assigns[:mcp_api_key]) ->
        to_string(conn.assigns.mcp_api_key.id)

      true ->
        nil
    end
  end

  @spec tenant_id(Plug.Conn.t()) :: String.t() | nil
  def tenant_id(%Plug.Conn{} = conn) do
    case conn.assigns[:mcp_account] do
      %{id: id} when not is_nil(id) -> to_string(id)
      _ -> nil
    end
  end

  @spec allowed_hosts() :: [String.t()]
  def allowed_hosts do
    :my_app
    |> Application.get_env(:mcp_allowed_hosts, ["localhost", "127.0.0.1", "::1", "[::1]"])
    |> Enum.map(&String.downcase/1)
  end

  @spec allowed_origins() :: [String.t()]
  def allowed_origins do
    Keyword.get(mcp_config(), :allowed_origins, [])
  end

  @spec allowed_origin?(String.t()) :: boolean()
  def allowed_origin?(origin) when is_binary(origin), do: origin in allowed_origins()
  def allowed_origin?(_), do: false

  defp mcp_config, do: Application.get_env(:my_app, :mcp, [])
end
```

AuthPlug calls `ExMCP.HttpPlug.init(Transport.plug_opts())` **per request** so
`handler_opts` sees the current assigns.

## Router

Do not `pipe_through :api` or `plug :accepts, ["json"]`.

Place this **outside** any `dev_routes` block:

```elixir
pipeline :mcp do
  plug :mcp_dns_rebinding
end

scope "/" do
  pipe_through :mcp

  get "/mcp", MyAppWeb.MCP.AuthPlug, []
  post "/mcp", MyAppWeb.MCP.AuthPlug, []
  delete "/mcp", MyAppWeb.MCP.AuthPlug, []
  options "/mcp", MyAppWeb.MCP.AuthPlug, []
end
```

Empty plug opts. Transport options live in `Transport.plug_opts/0`.

Keep the Phoenix Host allow-list so a disallowed Host is HTTP 403 **before**
auth. Pass the same list to ExMCP as `allowed_hosts` (native Host reject is
HTTP 421 if it runs first).

```elixir
def mcp_dns_rebinding(conn, _opts) do
  allowed =
    :my_app
    |> Application.get_env(:mcp_allowed_hosts, ["localhost", "127.0.0.1", "::1", "[::1]"])
    |> Enum.map(&String.downcase/1)
    |> Enum.map(&strip_host_brackets/1)

  host =
    conn.host
    |> Kernel.||("")
    |> String.downcase()
    |> strip_host_brackets()

  if host in allowed do
    conn
  else
    conn
    |> Plug.Conn.put_resp_content_type("text/plain")
    |> Plug.Conn.send_resp(403, "Forbidden: Invalid Host header")
    |> Plug.Conn.halt()
  end
end

defp strip_host_brackets("[" <> rest), do: String.trim_trailing(rest, "]")
defp strip_host_brackets(host) when is_binary(host), do: host
```

## Client config

Claude CLI:

```bash
claude mcp add --transport http my_app "http://localhost:4000/mcp" \
  --header "Authorization: Bearer YOUR_API_KEY"
```

`.mcp.json`:

```json
{
  "mcpServers": {
    "my_app": {
      "type": "http",
      "url": "http://localhost:4000/mcp",
      "headers": {
        "Authorization": "Bearer YOUR_API_KEY"
      }
    }
  }
}
```

MCP Inspector: transport **Streamable HTTP**, URL `http://localhost:4000/mcp`,
Bearer header on every method including GET SSE. After initialize, echo
`Mcp-Session-Id` on later calls.

curl:

```bash
curl -s http://localhost:4000/mcp \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```

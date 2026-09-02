# MCP tests and MCPCase

Replace `MyApp` / `MyAppWeb` with the detected names. Use the app's existing
user/api-key fixtures (`user_fixture`, `insert(:api_key)`, etc.).

Prefer ConnTest against the shipped `/mcp` route over calling `MCPServer`
functions in isolation.

## MCPCase

`test/support/mcp_case.ex`

Add `test/support` to `elixirc_paths` in `mix.exs` if it is not already there.

```elixir
defmodule MyAppWeb.MCPCase do
  @moduledoc "Helpers for driving the shipped Streamable HTTP MCP endpoint."

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint MyAppWeb.Endpoint

  @doc "POST a JSON-RPC request to `/mcp` and return `{conn, decoded_body}`."
  def mcp_rpc(conn, method, params \\ %{}, opts \\ []) do
    payload = %{
      "jsonrpc" => "2.0",
      "id" => Keyword.get(opts, :id, 1),
      "method" => method,
      "params" => params
    }

    conn =
      conn
      |> recycle_if_sent()
      |> put_mcp_headers()
      |> maybe_session(Keyword.get(opts, :session_id))
      |> maybe_token(Keyword.get(opts, :token))
      |> Phoenix.ConnTest.post("/mcp", Jason.encode!(payload))

    {conn, decode_body(conn.resp_body)}
  end

  @doc "POST a JSON-RPC notification (no `id`)."
  def mcp_notify(conn, method, params \\ %{}, opts \\ []) do
    conn =
      conn
      |> recycle_if_sent()
      |> put_mcp_headers()
      |> maybe_session(Keyword.get(opts, :session_id))
      |> maybe_token(Keyword.get(opts, :token))
      |> Phoenix.ConnTest.post("/mcp", Jason.encode!(%{
        "jsonrpc" => "2.0",
        "method" => method,
        "params" => params
      }))

    {conn, conn.resp_body}
  end

  @doc "Call a tool through JSON-RPC and decode its JSON text content."
  def call_tool(conn, name, args \\ %{}, opts \\ []) do
    {conn, body} =
      mcp_rpc(conn, "tools/call", %{"name" => name, "arguments" => args}, opts)

    {conn, body, tool_json(body)}
  end

  def tool_json(%{"result" => %{"content" => [%{"text" => text} | _]}}) do
    case Jason.decode(text) do
      {:ok, decoded} -> decoded
      {:error, _} -> text
    end
  end

  def tool_json(_), do: nil

  defp put_mcp_headers(conn) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("accept", "application/json, text/event-stream")
  end

  defp maybe_session(conn, nil), do: conn
  defp maybe_session(conn, session_id), do: put_req_header(conn, "mcp-session-id", session_id)

  defp maybe_token(conn, nil), do: conn
  defp maybe_token(conn, token), do: put_req_header(conn, "authorization", "Bearer #{token}")

  defp decode_body(bin) when is_binary(bin) and bin != "", do: Jason.decode!(bin)
  defp decode_body(_), do: nil

  defp recycle_if_sent(%Plug.Conn{state: state} = conn) when state != :unset, do: recycle(conn)
  defp recycle_if_sent(conn), do: conn
end
```

## Required ConnTests

`test/my_app_web/mcp_test.exs` — `async: false` is not required for ETS
AuthSessions (those modules are gone). Keep `async: false` only if the app
shares other global MCP state.

Cover:

- missing Bearer on POST → 401 `invalid_request`
- invalid Bearer → 401 `invalid_token`
- GET without Bearer → 401 (session id is not enough)
- initialize → 200, `serverInfo.name` set, `mcp-session-id` issued
- `notifications/initialized` → 202 empty body; does **not** mint a new session
- `tools/list` with that session + token → includes `ping`
- `ping` tool succeeds
- unrecognized `Origin` → 403 before tool dispatch
- missing `Origin` accepted for a valid CLI client
- disallowed Host → 403
- POST without `Accept: application/json` → 406
- unknown / cross-identity `mcp-session-id` after initialize → 400 or 404 JSON-RPC, not 401

```elixir
defmodule MyAppWeb.MCPTest do
  use MyAppWeb.ConnCase, async: true

  import MyAppWeb.MCPCase

  setup %{conn: conn} do
    {_api_key, token} = create_api_key_with_token(scopes: ["examples:read", "examples:write"])
    %{conn: conn, token: token}
  end

  test "initialize returns serverInfo and tools/list includes ping", %{conn: conn, token: token} do
    {conn, body} =
      mcp_rpc(
        conn,
        "initialize",
        %{
          "protocolVersion" => "2025-11-25",
          "capabilities" => %{},
          "clientInfo" => %{"name" => "exunit", "version" => "1"}
        },
        token: token
      )

    assert conn.status == 200
    assert body["result"]["serverInfo"]["name"] == "my_app"
    session_id = List.first(get_resp_header(conn, "mcp-session-id"))
    assert is_binary(session_id)

    {conn, resp} =
      mcp_notify(conn, "notifications/initialized", %{}, session_id: session_id, token: token)

    assert conn.status == 202
    assert resp in [nil, ""]

    {_conn, list_body} = mcp_rpc(conn, "tools/list", %{}, session_id: session_id, token: token)
    names = list_body |> get_in(["result", "tools"]) |> List.wrap() |> Enum.map(& &1["name"])
    assert "ping" in names
  end

  test "ping succeeds with a valid key", %{conn: conn, token: token} do
    {_conn, _body, json} = call_tool(conn, "ping", %{}, token: token)
    assert json["ok"] == true
  end

  test "missing bearer is 401", %{conn: conn} do
    {conn, body} = mcp_rpc(conn, "tools/list")
    assert conn.status == 401
    assert body["error"] == "invalid_request"
  end
end
```

Wire `create_api_key_with_token/1` to the app's fixtures. If keys use
`type: :public` instead of `scopes`, pass that.

Add a CacheBody test that forces a valid JSON-RPC body to span multiple
reads with a small `read_length` (`{:more, chunk}` then `{:ok, rest}`).

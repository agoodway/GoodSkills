# HTTP plugs, CacheBody, SSE

Replace `MyApp` / `MyAppWeb` with the detected names.

Detect the API-key verify function:

- `MyApp.Accounts.verify_api_token/1` (bootstrap-api-keys / bootstrap-openapi)
- `MyApp.Accounts.authenticate_api_key/1` (older)

Use whichever exists. Both should return `{:ok, api_key}` or `{:error, _}`.

## CacheBody

`lib/my_app_web/plugs/cache_body.ex`

Concatenate every `{:more, chunk}` and assign the complete body. The previous
reader only stashed the final `{:ok, body}` and dropped earlier fragments.

```elixir
defmodule MyAppWeb.Plugs.CacheBody do
  @moduledoc """
  Plug.Parsers `body_reader` that stashes the complete raw request body.

  `ExMCP.HttpPlug` reads `conn.assigns[:raw_body]` after Phoenix parsers
  consume the adapter body.
  """

  @spec read_body(Plug.Conn.t(), keyword()) ::
          {:ok, binary(), Plug.Conn.t()}
          | {:more, binary(), Plug.Conn.t()}
          | {:error, term()}
  def read_body(conn, opts) do
    limit = Keyword.get(opts, :length, 8_000_000)
    accumulate(conn, opts, conn.assigns[:raw_body] || "", limit)
  end

  defp accumulate(conn, opts, acc, limit) do
    case Plug.Conn.read_body(conn, Keyword.put(opts, :length, remaining(limit, acc))) do
      {:ok, body, conn} ->
        finish(conn, acc <> body, limit)

      {:more, chunk, conn} ->
        continue_or_stop(conn, opts, acc <> chunk, chunk, limit)

      other ->
        other
    end
  end

  defp remaining(limit, acc), do: max(limit - byte_size(acc), 0)

  defp finish(conn, body, limit) do
    conn = assign_raw(conn, body)

    if byte_size(body) > limit do
      {:more, body, conn}
    else
      {:ok, body, conn}
    end
  end

  defp continue_or_stop(conn, opts, full, chunk, limit) do
    conn = assign_raw(conn, full)

    if byte_size(full) >= limit do
      {:more, chunk, conn}
    else
      accumulate(conn, opts, full, limit)
    end
  end

  defp assign_raw(conn, body) when is_binary(body) do
    Plug.Conn.assign(conn, :raw_body, body)
  end
end
```

## Error

`lib/my_app_web/mcp/error.ex`

```elixir
defmodule MyAppWeb.MCP.Error do
  @moduledoc "JSON error responses for the MCP transport."

  import Plug.Conn

  alias MyApp.MCP.Transport

  @spec unauthorized(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def unauthorized(conn, error, description) do
    send_error(conn, 401, error, description)
  end

  @spec forbidden(Plug.Conn.t(), String.t(), String.t()) :: Plug.Conn.t()
  def forbidden(conn, error, description) do
    send_error(conn, 403, error, description)
  end

  @spec put_cors_origin(Plug.Conn.t()) :: Plug.Conn.t()
  def put_cors_origin(conn) do
    case List.first(get_req_header(conn, "origin")) do
      origin when is_binary(origin) ->
        if Transport.allowed_origin?(origin) do
          put_resp_header(conn, "access-control-allow-origin", origin)
        else
          conn
        end

      _missing ->
        conn
    end
  end

  defp send_error(conn, status, error, description) do
    conn
    |> put_resp_header("www-authenticate", www_authenticate(error, description))
    |> put_cors_origin()
    |> put_resp_header("vary", "Origin")
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{error: error, error_description: description}))
    |> halt()
  end

  defp www_authenticate(error, description) do
    Enum.join(
      [
        ~s(Bearer realm="my_app"),
        ~s(error="#{error}"),
        ~s(error_description="#{description}")
      ],
      ", "
    )
  end
end
```

Never set `Access-Control-Allow-Origin: *` on authenticated MCP errors.

## VaryOrigin

`lib/my_app_web/mcp/vary_origin.ex`

ExMCP 1.1 echoes an allowed Origin but does not set cache variance or expose
`mcp-session-id`. This adapter must **not** validate Origin, mint sessions, or
intercept notifications.

```elixir
defmodule MyAppWeb.MCP.VaryOrigin do
  @moduledoc """
  Adds MCP CORS variance and browser-readable session headers.
  """

  @behaviour Plug

  import Plug.Conn

  alias MyApp.MCP.Transport

  @allow_headers "content-type, authorization, mcp-protocol-version, mcp-session-id, last-event-id"
  @expose_headers "mcp-session-id, mcp-protocol-version"

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    register_before_send(conn, &put_mcp_cors_headers/1)
  end

  defp put_mcp_cors_headers(conn) do
    conn
    |> put_vary_origin()
    |> maybe_put_expose_headers()
    |> maybe_put_allow_headers()
  end

  defp put_vary_origin(conn) do
    case get_resp_header(conn, "vary") do
      [] ->
        put_resp_header(conn, "vary", "Origin")

      values ->
        if Enum.any?(values, &vary_includes_origin?/1) do
          conn
        else
          put_resp_header(conn, "vary", Enum.join(values ++ ["Origin"], ", "))
        end
    end
  end

  defp maybe_put_expose_headers(conn) do
    if allowed_request_origin?(conn) do
      put_resp_header(conn, "access-control-expose-headers", @expose_headers)
    else
      conn
    end
  end

  defp maybe_put_allow_headers(%{method: "OPTIONS"} = conn) do
    put_resp_header(conn, "access-control-allow-headers", @allow_headers)
  end

  defp maybe_put_allow_headers(conn), do: conn

  defp allowed_request_origin?(conn) do
    case List.first(get_req_header(conn, "origin")) do
      origin when is_binary(origin) -> Transport.allowed_origin?(origin)
      _missing -> false
    end
  end

  defp vary_includes_origin?(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.any?(&(String.trim(&1) == "Origin"))
  end
end
```

## SSEConn

`lib/my_app_web/mcp/sse_conn.ex`

```elixir
defmodule MyAppWeb.MCP.SSEConn do
  @moduledoc """
  `ExMCP.HttpPlug.SSEConnection` adapter.

  Bandit requires `Plug.Conn.chunk/2` on the HTTP request process. Legacy GET
  SSE handlers send iodata to `mcp_sse_owner`; modern POST streams already
  run on that process and chunk directly.
  """

  @behaviour ExMCP.HttpPlug.SSEConnection

  @impl true
  def chunk(%Plug.Conn{} = conn, iodata) do
    case conn.assigns[:mcp_sse_owner] do
      owner when is_pid(owner) ->
        send(owner, {:sse_chunk, iodata})
        {:ok, conn}

      _missing ->
        Plug.Conn.chunk(conn, iodata)
    end
  end

  def chunk(_conn, _message), do: {:error, :not_supported}

  @impl true
  def get_req_header(%Plug.Conn{} = conn, header), do: Plug.Conn.get_req_header(conn, header)
  def get_req_header(_conn, _header), do: []
end
```

## SSE (Bandit-safe owner loop)

`lib/my_app_web/mcp/sse.ex`

`ExMCP.HttpPlug.SSEHandler` owns sessions, replay, and events. This module
only `send_chunked/2` and `chunk/2` on the request process.

Session failures are HTTP **400/404 JSON-RPC**. OAuth/API-key HTTP 401 is
reserved for Bearer failures. GET still requires Bearer in AuthPlug before
this module runs.

```elixir
defmodule MyAppWeb.MCP.SSE do
  @moduledoc """
  Bandit-safe owner loop for ExMCP legacy GET SSE.
  """

  import Plug.Conn

  alias ExMCP.HttpPlug.SessionRegistry
  alias ExMCP.HttpPlug.SSEHandler
  alias ExMCP.Protocol.ErrorCodes
  alias ExMCP.SessionManager
  alias MyApp.MCP.Transport
  alias MyAppWeb.MCP.Error
  alias MyAppWeb.MCP.SSEConn

  @heartbeat_ms 30_000
  @session_id_max_bytes 128

  @spec serve(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def serve(conn, opts) when is_map(opts) do
    session_manager = Map.get(opts, :session_manager, SessionManager)

    with :ok <- validate_origin(conn, opts),
         {:ok, session_id} <- fetch_session_id(conn),
         :ok <- ensure_session(conn, session_id, session_manager) do
      stream(conn, session_id, opts, session_manager)
    else
      {:error, :origin_not_allowed} ->
        conn
        |> Error.put_cors_origin()
        |> send_resp(403, "Origin not allowed")
        |> halt()

      {:error, :session_required} ->
        jsonrpc_error(conn, 400, "Session ID required")

      {:error, :invalid_session_id} ->
        jsonrpc_error(conn, 400, "Invalid session ID")

      {:error, reason}
      when reason in [
             :session_expired,
             :session_not_found,
             :session_identity_mismatch,
             :session_not_initialized
           ] ->
        jsonrpc_error(conn, 404, "Session not found")
    end
  end

  defp stream(conn, session_id, opts, session_manager) do
    conn =
      conn
      |> Error.put_cors_origin()
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("x-accel-buffering", "no")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    conn = assign(conn, :mcp_sse_owner, self())
    opts = Map.put(opts, :conn_module, SSEConn)
    {:ok, handler} = SSEHandler.start_link(conn, session_id, opts)
    true = Process.unlink(handler)
    watcher = spawn(fn -> watch_owner(self(), handler, session_id) end)
    register_handler(session_id, handler, session_manager)

    try do
      loop(conn, handler, Process.monitor(handler), session_id)
    after
      Process.exit(watcher, :kill)
    end
  end

  defp watch_owner(owner, handler, session_id) do
    owner_ref = Process.monitor(owner)
    handler_ref = Process.monitor(handler)

    receive do
      {:DOWN, ^owner_ref, :process, ^owner, _reason} ->
        close_sse_handler(handler)
        SessionRegistry.unregister(session_id, handler)

      {:DOWN, ^handler_ref, :process, ^handler, _reason} ->
        :ok
    end
  end

  defp loop(conn, handler, ref, session_id) do
    receive do
      {:sse_chunk, iodata} ->
        case chunk(conn, iodata) do
          {:ok, conn} -> loop(conn, handler, ref, session_id)
          {:error, _reason} -> close_handler(conn, handler, session_id)
        end

      {:DOWN, ^ref, :process, ^handler, _reason} ->
        SessionRegistry.unregister(session_id, handler)
        conn
    after
      @heartbeat_ms ->
        case chunk(conn, ": heartbeat\n\n") do
          {:ok, conn} -> loop(conn, handler, ref, session_id)
          {:error, _reason} -> close_handler(conn, handler, session_id)
        end
    end
  end

  defp close_handler(conn, handler, session_id) do
    close_sse_handler(handler)
    SessionRegistry.unregister(session_id, handler)
    conn
  end

  defp register_handler(session_id, handler, session_manager) do
    previous =
      case SessionRegistry.lookup(session_id) do
        {:ok, pid} when pid != handler -> pid
        _other -> nil
      end

    _ = SessionRegistry.register(session_id, handler)

    if function_exported?(session_manager, :update_session, 2) do
      session_manager.update_session(session_id, %{handler_pid: handler})
    end

    if is_pid(previous), do: close_sse_handler(previous)
    _ = SSEHandler.replay(handler)
    :ok
  end

  defp close_sse_handler(pid) do
    SSEHandler.close(pid)
  catch
    :exit, _ -> :ok
  end

  defp validate_origin(conn, opts) do
    if Map.get(opts, :validate_origin, true) do
      case List.first(get_req_header(conn, "origin")) do
        nil ->
          :ok

        origin ->
          allowed = Map.get(opts, :allowed_origins, Transport.allowed_origins())
          if origin in allowed, do: :ok, else: {:error, :origin_not_allowed}
      end
    else
      :ok
    end
  end

  defp fetch_session_id(conn) do
    case get_req_header(conn, "mcp-session-id") do
      [] -> {:error, :session_required}
      [id] -> validate_session_id(id)
      _multiple -> {:error, :invalid_session_id}
    end
  end

  defp validate_session_id(id) when byte_size(id) in 1..@session_id_max_bytes do
    if session_id_chars?(id), do: {:ok, id}, else: {:error, :invalid_session_id}
  end

  defp validate_session_id(_id), do: {:error, :invalid_session_id}

  defp session_id_chars?(<<>>), do: true

  defp session_id_chars?(<<c, rest::binary>>)
       when c in ?A..?Z or c in ?a..?z or c in ?0..?9 or c in [?., ?_, ?~, ?+, ?/, ?=, ?-] do
    session_id_chars?(rest)
  end

  defp session_id_chars?(_other), do: false

  defp ensure_session(conn, session_id, session_manager) do
    case session_manager.get_session(session_id) do
      {:ok, session} -> confirm_session(conn, session_id, session, session_manager)
      {:error, reason} -> {:error, reason}
    end
  end

  defp confirm_session(conn, session_id, session, session_manager) do
    if session.principal_id == Transport.principal_id(conn) and
         session.tenant_id == Transport.tenant_id(conn) do
      session_manager.ensure_initialized_session(session_id, %{
        principal_id: session.principal_id,
        tenant_id: session.tenant_id,
        issuer: session.issuer,
        audience: session.audience,
        transport: :sse
      })
    else
      {:error, :session_identity_mismatch}
    end
  end

  defp jsonrpc_error(conn, status, message) do
    body =
      Jason.encode!(%{
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => %{"code" => ErrorCodes.invalid_request(), "message" => message}
      })

    conn
    |> Error.put_cors_origin()
    |> put_resp_content_type("application/json")
    |> send_resp(status, body)
    |> halt()
  end
end
```

## AuthPlug

`lib/my_app_web/mcp/auth_plug.ex`

Requires a Bearer API key on GET, POST, and DELETE. OPTIONS is
credential-free. Phoenix session cookies are ignored. A session header is
an extra native-session binding, never a substitute credential.

```elixir
defmodule MyAppWeb.MCP.AuthPlug do
  @moduledoc """
  Requires a Bearer API key on MCP GET, POST, and DELETE.
  """

  @behaviour Plug

  import Plug.Conn

  alias MyApp.Accounts
  alias MyApp.MCP.Transport
  alias MyAppWeb.MCP.Error
  alias MyAppWeb.MCP.SSE
  alias MyAppWeb.MCP.SSEConn
  alias MyAppWeb.MCP.VaryOrigin

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Plug.Conn{method: "OPTIONS"} = conn, _opts) do
    conn
    |> VaryOrigin.call([])
    |> ExMCP.HttpPlug.call(http_plug_opts(conn))
  end

  def call(%Plug.Conn{method: method} = conn, _opts)
      when method in ["GET", "POST", "DELETE"] do
    authorize_bearer(conn)
  end

  def call(conn, _opts) do
    conn
    |> VaryOrigin.call([])
    |> ExMCP.HttpPlug.call(http_plug_opts(conn))
  end

  defp authorize_bearer(conn) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, api_key} <- verify_api_key(token) do
      conn
      |> assign(:mcp_api_key, api_key)
      |> assign(:mcp_api_key_id, api_key.id)
      |> dispatch()
    else
      :error -> missing_bearer(conn)
      {:error, _reason} -> invalid_bearer(conn)
    end
  end

  defp dispatch(conn) do
    conn
    |> VaryOrigin.call([])
    |> call_or_reject_accept()
  end

  defp call_or_reject_accept(conn) do
    if acceptable_mcp?(conn) do
      dispatch_hex(conn)
    else
      reject_accept(conn)
    end
  end

  defp dispatch_hex(%{method: "GET"} = conn) do
    opts = http_plug_opts(conn)

    if Map.get(opts, :sse_mode) == :oneshot do
      ExMCP.HttpPlug.call(conn, opts)
    else
      SSE.serve(conn, opts)
    end
  end

  defp dispatch_hex(conn) do
    ExMCP.HttpPlug.call(conn, http_plug_opts(conn))
  end

  defp http_plug_opts(_conn) do
    opts =
      Transport.plug_opts()
      |> ExMCP.HttpPlug.init()
      |> Map.put(:conn_module, SSEConn)

    Map.put(opts, :sse_mode, Application.get_env(:ex_mcp, :sse_mode, opts.sse_mode))
  end

  defp acceptable_mcp?(%{method: "GET"} = conn) do
    accept_has_type?(conn, "text/event-stream")
  end

  defp acceptable_mcp?(%{method: "POST"} = conn) do
    accept_has_type?(conn, "application/json")
  end

  defp acceptable_mcp?(_conn), do: true

  defp accept_has_type?(conn, type) do
    conn
    |> get_req_header("accept")
    |> Enum.flat_map(&accept_tokens/1)
    |> Enum.member?(type)
  end

  defp accept_tokens(header) do
    header
    |> String.split(",", trim: true)
    |> Enum.map(fn part ->
      part |> String.split(";", parts: 2) |> hd() |> String.trim() |> String.downcase()
    end)
  end

  defp reject_accept(conn) do
    conn
    |> Error.put_cors_origin()
    |> put_resp_header("vary", "Origin")
    |> put_resp_content_type("application/json")
    |> send_resp(406, Jason.encode!(%{error: "Not Acceptable"}))
    |> halt()
  end

  defp verify_api_key(token) do
    cond do
      function_exported?(Accounts, :verify_api_token, 1) ->
        Accounts.verify_api_token(token)

      function_exported?(Accounts, :authenticate_api_key, 1) ->
        Accounts.authenticate_api_key(token)

      true ->
        {:error, :not_configured}
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] when byte_size(token) > 0 -> {:ok, token}
      _ -> :error
    end
  end

  defp missing_bearer(conn) do
    Error.unauthorized(
      conn,
      "invalid_request",
      "Authorization header with Bearer token is required."
    )
  end

  defp invalid_bearer(conn) do
    Error.unauthorized(
      conn,
      "invalid_token",
      "The API key is invalid, expired, or revoked."
    )
  end
end
```

Call the concrete verify function directly once discovery has picked one;
leave the `function_exported?` branch only when both names might exist.

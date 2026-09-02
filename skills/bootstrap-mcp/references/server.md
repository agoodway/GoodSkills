# MCPServer

Replace `MyApp` / `MyAppWeb` with the detected names.

Use ExMCP 1.1 DSL (`ExMCP.Server.Handler` + `ExMCP.Server.DSL`). Do **not**
`use ExMCP.Server` or `deftool`. Do **not** generate a thin `Handler` or
`RequestHandler`. Do **not** store identity in the process dictionary.

Customize `example_*` tools to a real context. Keep `ping` as the smoke test.

`lib/my_app/mcp_server.ex`

```elixir
defmodule MyApp.MCPServer do
  @moduledoc """
  Temporary request-local ExMCP handler.

  Identity comes from handler state (`:api_key`) passed through
  `MyApp.MCP.Transport.handler_opts/1`.
  """

  use ExMCP.Server.Handler
  use ExMCP.Server.DSL, name: "my_app", version: "0.1.0"

  @impl GenServer
  def init(opts) when is_map(opts) do
    {:ok, Map.put_new(opts, :scopes, [])}
  end

  def init(opts) when is_list(opts) do
    init(%{
      api_key: Keyword.get(opts, :api_key),
      user: Keyword.get(opts, :user),
      account: Keyword.get(opts, :account),
      scopes: Keyword.get(opts, :scopes, [])
    })
  end

  tool "ping", "Health check. Returns ok." do
    title("Ping")
    annotations readOnlyHint: true

    input_schema(%{
      type: "object",
      properties: %{},
      additionalProperties: false
    })

    run(fn _args, state ->
      with_scope("examples:read", state, fn _api_key ->
        {:ok, %{content: [json(%{ok: true})]}, state}
      end)
    end)
  end

  tool "example_list", "List examples with pagination and search" do
    title("List Examples")
    annotations readOnlyHint: true

    input_schema(%{
      type: "object",
      properties: %{
        page: %{type: "integer"},
        per_page: %{type: "integer"},
        search: %{type: "string"}
      },
      additionalProperties: false
    })

    run(fn args, state ->
      with_scope("examples:read", state, fn _api_key ->
        {page, per_page} = pagination(args)
        search = arg(args, :search)
        {items, total} = list_examples(page, per_page, search)
        meta = build_meta(page, per_page, total)
        {:ok, %{content: [json(%{success: true, data: items, meta: meta})]}, state}
      end)
    end)
  end

  tool "example_get", "Get a single example by ID" do
    title("Get Example")
    annotations readOnlyHint: true

    input_schema(%{
      type: "object",
      properties: %{id: %{type: "string"}},
      required: ["id"],
      additionalProperties: false
    })

    run(fn args, state ->
      with_scope("examples:read", state, fn _api_key ->
        example = MyApp.YourContext.get_example!(arg(args, :id))
        {:ok, %{content: [json(%{success: true, data: serialize(example)})]}, state}
      end)
    end)
  end

  tool "example_create", "Create a new example" do
    title("Create Example")

    input_schema(%{
      type: "object",
      properties: %{
        name: %{type: "string"},
        description: %{type: "string"}
      },
      required: ["name"],
      additionalProperties: false
    })

    run(fn args, state ->
      with_scope("examples:write", state, fn _api_key ->
        attrs = %{
          "name" => arg(args, :name),
          "description" => arg(args, :description)
        }

        case MyApp.YourContext.create_example(attrs) do
          {:ok, example} ->
            {:ok, %{content: [json(%{success: true, data: serialize(example)})]}, state}

          {:error, changeset} ->
            {:error, changeset_message(changeset), state}
        end
      end)
    end)
  end

  @doc false
  def with_scope(required_scope, state, fun) do
    case current_api_key(state) do
      nil ->
        {:error, "Authentication required", state}

      api_key ->
        if has_scope?(api_key, required_scope) do
          try do
            fun.(api_key)
          rescue
            Ecto.NoResultsError ->
              {:error, "Resource not found", state}

            exception ->
              require Logger
              Logger.error("MCP tool error: #{Exception.message(exception)}")
              {:error, "Internal server error", state}
          end
        else
          {:error, "Insufficient permissions. Required scope: #{required_scope}", state}
        end
    end
  end

  defp current_api_key(%{api_key: api_key}) when not is_nil(api_key), do: api_key
  defp current_api_key(_), do: nil

  defp has_scope?(api_key, required), do: required in scopes_for(api_key)

  defp scopes_for(%{scopes: scopes}) when is_list(scopes), do: scopes

  defp scopes_for(%{type: :private}),
    do: ["examples:read", "examples:write", "examples:delete"]

  defp scopes_for(%{type: :public}), do: ["examples:read"]
  defp scopes_for(_), do: []

  defp json(data), do: %{"type" => "text", "text" => Jason.encode!(data)}

  defp arg(args, key) when is_atom(key) do
    Map.get(args, key) || Map.get(args, Atom.to_string(key))
  end

  defp pagination(args) do
    page = args |> arg(:page) |> positive_int(1)
    per_page = args |> arg(:per_page) |> positive_int(50) |> min(250)
    {page, per_page}
  end

  defp positive_int(n, _default) when is_integer(n) and n > 0, do: n
  defp positive_int(_, default), do: default

  defp build_meta(page, per_page, total_count) do
    total_pages = if per_page == 0, do: 0, else: ceil(total_count / per_page)

    %{
      page: page,
      per_page: per_page,
      total_count: total_count,
      total_pages: total_pages,
      has_next: page < total_pages,
      has_prev: page > 1
    }
  end

  defp changeset_message(changeset) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
        Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    "Validation failed: #{Jason.encode!(errors)}"
  end

  defp list_examples(page, per_page, search) do
    import Ecto.Query
    query = from(e in MyApp.YourContext.Example)

    query =
      if is_binary(search) and search != "" do
        pattern = "%#{escape_like(search)}%"
        where(query, [e], ilike(e.name, ^pattern))
      else
        query
      end

    total = MyApp.Repo.aggregate(query, :count)

    items =
      query
      |> order_by([e], desc: e.inserted_at)
      |> limit(^per_page)
      |> offset(^((page - 1) * per_page))
      |> MyApp.Repo.all()
      |> Enum.map(&serialize/1)

    {items, total}
  end

  defp serialize(example) do
    %{
      id: example.id,
      name: example.name,
      description: example.description,
      inserted_at: DateTime.to_iso8601(example.inserted_at),
      updated_at: DateTime.to_iso8601(example.updated_at)
    }
  end

  defp escape_like(nil), do: nil

  defp escape_like(string) when is_binary(string) do
    string
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end
end
```

If `YourContext` does not exist yet, ship only `ping` and add the example
tools once the domain is real. Do not leave non-compiling aliases.

DSL args may be atom or string keys. Always read with `arg/2`.

Let ExMCP generate `InitializeResult` and negotiate protocol versions. Do
not hard-code a protocol version or patch `serverInfo`.

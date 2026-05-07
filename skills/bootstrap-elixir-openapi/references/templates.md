# Elixir OpenAPI Client Templates

Placeholders: `{{APP_NAME}}` (snake_case, e.g. `goodverify_ex`), `{{APP_ATOM}}` (e.g. `:goodverify_ex`), `{{MODULE_NAME}}` (PascalCase, e.g. `GoodverifyEx`), `{{BASE_URL}}` (e.g. `https://api.example.com`), `{{DEFAULT_BASE_URL}}` (e.g. `http://localhost:4000`), `{{PATH_PREFIX}}` (e.g. `/api/v1/`), `{{API_NAME}}` (human name, e.g. "GoodVerify").

## mix.exs

```elixir
defmodule {{MODULE_NAME}}.MixProject do
  use Mix.Project

  def project do
    [
      app: {{APP_ATOM}},
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:mimic, "~> 2.0", only: :test}
    ]
  end
end
```

## .formatter.exs

```elixir
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
]
```

## Main module — `lib/{{APP_NAME}}.ex`

This module reads the OpenAPI spec at compile time and generates one public function per API operation.

```elixir
defmodule {{MODULE_NAME}} do
  @moduledoc """
  Elixir client for the {{API_NAME}} API, generated from the OpenAPI specification.

  ## Configuration

      config {{APP_ATOM}},
        base_url: "{{BASE_URL}}",
        api_key: "your-api-key"

  ## Usage

      client = {{MODULE_NAME}}.client(api_key: "sk_...")
      {:ok, result} = {{MODULE_NAME}}.some_endpoint(client, %{param: "value"})
  """

  @spec_path Path.join([__DIR__, "..", "openapi.json"])
  @external_resource @spec_path
  @openapi_spec File.read!(@spec_path) |> Jason.decode!()

  alias {{MODULE_NAME}}.Client

  @doc "Create a new API client."
  def client(opts \\ []), do: Client.new(opts)

  # Generate API functions from OpenAPI paths
  for {path, methods} <- @openapi_spec["paths"],
      {method, operation} <- methods do
    func_name =
      path
      |> String.replace_prefix("{{PATH_PREFIX}}", "")
      |> String.replace("/", "_")
      |> String.to_atom()

    http_method = String.to_atom(method)
    summary = operation["summary"] || ""
    description = operation["description"] || ""

    response_ref =
      get_in(operation, ["responses", "200", "content", "application/json", "schema", "$ref"])

    response_module =
      if response_ref do
        ref_name = response_ref |> String.split("/") |> List.last()
        Module.concat({{MODULE_NAME}}.Schemas, ref_name)
      end

    has_body = operation["requestBody"] != nil

    if has_body do
      @doc "#{summary}\n\n#{description}"
      def unquote(func_name)(%Client{} = client, params) when is_map(params) do
        case Client.request(client, unquote(http_method), unquote(path), json: params) do
          {:ok, body} when is_map(body) ->
            {:ok, unquote(response_module).from_map(body)}

          error ->
            error
        end
      end
    else
      @doc "#{summary}\n\n#{description}"
      def unquote(func_name)(%Client{} = client) do
        case Client.request(client, unquote(http_method), unquote(path)) do
          {:ok, body} when is_map(body) ->
            {:ok, unquote(response_module).from_map(body)}

          error ->
            error
        end
      end
    end
  end
end
```

### Handling path parameters

When a path contains `{param}` segments (e.g. `/users/{id}`), the generated function must accept path parameters as arguments and interpolate them into the URL at request time.

```elixir
# For a path like /users/{user_id}/posts/{post_id} with GET:
# Extract param names: [:user_id, :post_id]
# Generate:

@doc "..."
def get_user_posts(%Client{} = client, user_id, post_id) do
  path = "/users/#{user_id}/posts/#{post_id}"
  case Client.request(client, :get, path) do
    {:ok, body} when is_map(body) ->
      {:ok, ResponseModule.from_map(body)}
    error ->
      error
  end
end
```

The function name derivation for parameterized paths:
- Strip the prefix: `/api/v1/users/{user_id}` -> `users/{user_id}`
- Replace `{param}` segments with nothing or a meaningful name
- If `operationId` exists, prefer that (converted to snake_case atom)
- Otherwise: `/users/{id}` + GET -> `get_user`, `/users/{id}` + DELETE -> `delete_user`

### Handling operations without 200 response schema

If an operation has no 200 response with a JSON schema (e.g. 204 No Content):

```elixir
def unquote(func_name)(%Client{} = client) do
  case Client.request(client, unquote(http_method), unquote(path)) do
    {:ok, _body} -> :ok
    error -> error
  end
end
```

## Client module — `lib/{{APP_NAME}}/client.ex`

### Bearer token auth (default)

```elixir
defmodule {{MODULE_NAME}}.Client do
  @moduledoc """
  HTTP client for the {{API_NAME}} API.

  Configuration can be provided explicitly or via application config:

      config {{APP_ATOM}},
        base_url: "{{BASE_URL}}",
        api_key: "your-api-key"
  """

  @type t :: %__MODULE__{
          base_url: String.t(),
          api_key: String.t() | nil,
          req_options: keyword()
        }

  defstruct [:base_url, :api_key, req_options: []]

  @doc "Create a new client with the given options."
  def new(opts \\ []) do
    %__MODULE__{
      base_url:
        Keyword.get(opts, :base_url) ||
          Application.get_env({{APP_ATOM}}, :base_url, "{{DEFAULT_BASE_URL}}"),
      api_key:
        Keyword.get(opts, :api_key) ||
          Application.get_env({{APP_ATOM}}, :api_key),
      req_options: Keyword.get(opts, :req_options, [])
    }
  end

  @doc false
  def request(%__MODULE__{} = client, method, path, opts \\ []) do
    headers = build_headers(client)

    req_opts =
      [method: method, url: client.base_url <> path, headers: headers]
      |> Keyword.merge(opts)
      |> Keyword.merge(client.req_options)

    case Req.request(req_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, %{status: status, body: body}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  defp build_headers(%{api_key: nil}), do: []
  defp build_headers(%{api_key: key}), do: [{"authorization", "Bearer #{key}"}]
end
```

### API key header auth variant

If the API uses a custom header (e.g. `X-API-Key`):

```elixir
  defp build_headers(%{api_key: nil}), do: []
  defp build_headers(%{api_key: key}), do: [{"{{HEADER_NAME}}", key}]
```

### No auth variant

```elixir
  defp build_headers(_client), do: []
```

## Schemas module — `lib/{{APP_NAME}}/schemas.ex`

```elixir
defmodule {{MODULE_NAME}}.Schemas do
  @moduledoc """
  Generated schema structs from the {{API_NAME}} OpenAPI specification.

  Each schema from `openapi.json` is compiled into an Elixir struct module
  with a `from_map/1` function that recursively converts JSON-decoded maps
  into typed structs, resolving `$ref`, `anyOf`, `allOf`, and array references.

  Recompiles automatically when `openapi.json` changes.
  """

  @spec_path Path.join([__DIR__, "..", "..", "openapi.json"])
  @external_resource @spec_path
  @openapi_spec File.read!(@spec_path) |> Jason.decode!()

  for {schema_name, schema_def} <- @openapi_spec["components"]["schemas"] do
    mod_name = Module.concat(__MODULE__, schema_name)
    props = schema_def["properties"] || %{}
    desc = schema_def["description"] || ""

    field_names = props |> Map.keys() |> Enum.sort() |> Enum.map(&String.to_atom/1)

    # Build a map of field_name => conversion rule for nested types
    conversions =
      for {prop_name, prop_def} <- props, into: %{} do
        conv =
          cond do
            match?(%{"$ref" => _}, prop_def) ->
              {:struct, prop_def["$ref"] |> String.split("/") |> List.last()}

            is_list(prop_def["anyOf"]) ->
              case Enum.find(prop_def["anyOf"], &match?(%{"$ref" => _}, &1)) do
                %{"$ref" => ref} -> {:struct, ref |> String.split("/") |> List.last()}
                _ -> :passthrough
              end

            is_list(prop_def["allOf"]) ->
              case Enum.find(prop_def["allOf"], &match?(%{"$ref" => _}, &1)) do
                %{"$ref" => ref} -> {:struct, ref |> String.split("/") |> List.last()}
                _ -> :passthrough
              end

            prop_def["type"] == "array" && is_map(prop_def["items"]) &&
                Map.has_key?(prop_def["items"], "$ref") ->
              {:list, prop_def["items"]["$ref"] |> String.split("/") |> List.last()}

            true ->
              :passthrough
          end

        {String.to_atom(prop_name), conv}
      end

    escaped_conversions = Macro.escape(conversions)

    Module.create(
      mod_name,
      quote do
        @moduledoc unquote(desc)

        defstruct unquote(field_names)

        @field_set MapSet.new(unquote(field_names))
        @conversions unquote(escaped_conversions)

        @doc "Convert a JSON-decoded map into a `#{inspect(__MODULE__)}` struct."
        def from_map(nil), do: nil

        def from_map(map) when is_map(map) do
          fields =
            for {key, value} <- map,
                atom_key = to_field_atom(key),
                atom_key in @field_set,
                into: %{} do
              {atom_key, convert_field(atom_key, value)}
            end

          struct(__MODULE__, fields)
        end

        defp to_field_atom(key) when is_atom(key), do: key
        defp to_field_atom(key) when is_binary(key), do: String.to_atom(key)

        defp convert_field(_key, nil), do: nil

        defp convert_field(key, value) do
          case Map.get(@conversions, key) do
            {:struct, ref_name} when is_map(value) ->
              Module.concat(unquote({{MODULE_NAME}}.Schemas), ref_name).from_map(value)

            {:list, ref_name} when is_list(value) ->
              mod = Module.concat(unquote({{MODULE_NAME}}.Schemas), ref_name)
              Enum.map(value, &mod.from_map/1)

            _ ->
              value
          end
        end
      end,
      __ENV__
    )
  end
end
```

**Important**: In the `convert_field` function, the `Module.concat` call must reference the correct top-level Schemas module for the specific project. Replace `{{MODULE_NAME}}.Schemas` with the actual module name (e.g. `GoodverifyEx.Schemas`).

## test_helper.exs

```elixir
Mimic.copy(Req)
ExUnit.start()
```

## Unit test template — `test/{{APP_NAME}}_test.exs`

```elixir
defmodule {{MODULE_NAME}}Test do
  use ExUnit.Case

  alias {{MODULE_NAME}}.Client
  alias {{MODULE_NAME}}.Schemas

  describe "client/1" do
    test "creates client with defaults" do
      client = {{MODULE_NAME}}.client()
      assert %Client{base_url: "{{DEFAULT_BASE_URL}}", api_key: nil} = client
    end

    test "creates client with explicit options" do
      client = {{MODULE_NAME}}.client(base_url: "https://api.example.com", api_key: "sk_test")
      assert client.base_url == "https://api.example.com"
      assert client.api_key == "sk_test"
    end
  end

  describe "schema from_map/1" do
    # Add tests for 2-3 representative schemas from the spec.
    # Include:
    # - A simple flat schema
    # - A schema with nested $ref fields
    # - A schema with array-of-ref fields (if any)

    test "handles nil values" do
      # Pick any schema:
      # assert nil == Schemas.SomeSchema.from_map(nil)
    end

    test "ignores unknown fields" do
      # result = Schemas.SomeSchema.from_map(%{"known" => "val", "unknown" => "ignored"})
      # assert result.known == "val"
    end
  end

  describe "generated API functions" do
    test "all expected functions are generated" do
      Code.ensure_loaded!({{MODULE_NAME}})
      # assert function_exported?({{MODULE_NAME}}, :func_name, arity)
    end
  end
end
```

## Integration test template — `test/{{APP_NAME}}/integration_test.exs`

```elixir
defmodule {{MODULE_NAME}}.IntegrationTest do
  use ExUnit.Case, async: true
  use Mimic

  alias {{MODULE_NAME}}.Schemas

  setup :verify_on_exit!

  @client {{MODULE_NAME}}.client(base_url: "{{BASE_URL}}", api_key: "sk_test_123")

  defp json_response(status, body) do
    {:ok, %Req.Response{status: status, body: body}}
  end

  # For each generated API function, add a describe block:
  #
  # describe "func_name/arity" do
  #   test "success case" do
  #     expect(Req, :request, fn opts ->
  #       assert opts[:method] == :http_method
  #       assert opts[:url] == "{{BASE_URL}}/path"
  #       assert opts[:headers] == [{"authorization", "Bearer sk_test_123"}]
  #
  #       json_response(200, %{...mock response data...})
  #     end)
  #
  #     assert {:ok, result} = {{MODULE_NAME}}.func_name(@client, %{...params...})
  #     assert %Schemas.ResponseType{} = result
  #     # Assert specific field values
  #   end
  #
  #   test "error case" do
  #     expect(Req, :request, fn _opts ->
  #       json_response(422, %{"error" => %{"code" => "...", "message" => "..."}})
  #     end)
  #
  #     assert {:error, %{status: 422, body: body}} = {{MODULE_NAME}}.func_name(@client, %{...})
  #   end
  # end

  # Transport errors
  describe "transport errors" do
    test "returns error on connection failure" do
      expect(Req, :request, fn _opts ->
        {:error, %Req.TransportError{reason: :econnrefused}}
      end)

      # assert {:error, %Req.TransportError{reason: :econnrefused}} =
      #          {{MODULE_NAME}}.some_func(@client)
    end

    test "returns error on timeout" do
      expect(Req, :request, fn _opts ->
        {:error, %Req.TransportError{reason: :timeout}}
      end)

      # assert {:error, %Req.TransportError{reason: :timeout}} =
      #          {{MODULE_NAME}}.some_func(@client, %{...})
    end
  end

  # Auth header tests
  describe "client configuration" do
    test "does not send auth header when api_key is nil" do
      client = {{MODULE_NAME}}.client(base_url: "{{BASE_URL}}")

      expect(Req, :request, fn opts ->
        assert opts[:headers] == []
        json_response(200, %{...})
      end)

      # assert {:ok, _} = {{MODULE_NAME}}.some_func(client)
    end

    test "req_options are merged into requests" do
      client =
        {{MODULE_NAME}}.client(
          base_url: "{{BASE_URL}}",
          api_key: "sk_test_123",
          req_options: [receive_timeout: 30_000]
        )

      expect(Req, :request, fn opts ->
        assert opts[:receive_timeout] == 30_000
        json_response(200, %{...})
      end)

      # assert {:ok, _} = {{MODULE_NAME}}.some_func(client)
    end
  end
end
```

## README template

```markdown
# {{MODULE_NAME}}

Elixir client for the [{{API_NAME}}]({{API_URL}}) API. {{ONE_LINE_DESCRIPTION}}.

## Installation

Add `{{APP_NAME}}` to your dependencies in `mix.exs`:

\`\`\`elixir
def deps do
  [
    {{{APP_ATOM}}, "~> 0.1.0"}
  ]
end
\`\`\`

## Configuration

### Application config

\`\`\`elixir
# config/config.exs
config {{APP_ATOM}},
  base_url: "{{BASE_URL}}",
  api_key: "your-api-key"
\`\`\`

### Runtime / per-request

\`\`\`elixir
client = {{MODULE_NAME}}.client(
  base_url: "{{BASE_URL}}",
  api_key: "your-api-key"
)
\`\`\`

You can also pass `req_options` to customize the underlying [Req](https://hexdocs.pm/req) HTTP client:

\`\`\`elixir
client = {{MODULE_NAME}}.client(
  api_key: "your-api-key",
  req_options: [receive_timeout: 30_000]
)
\`\`\`

## Usage

Every function takes a `%{{MODULE_NAME}}.Client{}` as the first argument and returns `{:ok, struct}` or `{:error, reason}`.

<!-- Add usage examples for each endpoint -->

## Error handling

API errors return `{:error, %{status: integer, body: map}}`:

\`\`\`elixir
case {{MODULE_NAME}}.some_endpoint(client, %{param: "value"}) do
  {:ok, result} ->
    # handle success

  {:error, %{status: 422, body: body}} ->
    # validation error

  {:error, %{status: 401}} ->
    # invalid API key

  {:error, %{status: 429}} ->
    # rate limited

  {:error, %Req.TransportError{reason: reason}} ->
    # connection error (:econnrefused, :timeout, etc.)
end
\`\`\`

## Response types

All responses are typed structs under `{{MODULE_NAME}}.Schemas`. Schemas are generated at compile time from `openapi.json` and recompile automatically when the spec changes.

| Function | Response struct |
|----------|---------------|
<!-- Add table rows for each function -->

## Testing

The test suite uses [Mimic](https://hex.pm/packages/mimic) to mock `Req` HTTP calls:

\`\`\`sh
mix test
\`\`\`

## License

See [LICENSE](LICENSE) for details.
```

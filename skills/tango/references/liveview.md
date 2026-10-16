# LiveView connect button

`Tango.Live.OAuthComponent` creates an authorization session, opens the provider in a popup through the `TangoOAuth` JS hook, validates the callback message, and sends the parent LiveView only an opaque completion handle. The parent must still verify and finalize on the server ([authorization.md](authorization.md)). Requires Tango 0.2.0; `completion_origin` is mandatory.

## Prerequisites

- `Tango.API.Router` mounted ([api.md](api.md)); `callback_url` points at its `/callback`.
- `allowed_completion_origins` includes the LiveView page origin.
- A verifier module and a `complete/3`-style function from [authorization.md](authorization.md).

## Register the hook

```javascript
// assets/js/app.js
import TangoOAuth from "../../deps/tango/assets/tango_oauth_hook.js"

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { ...existingHooks, TangoOAuth },  // keep whatever hooks app.js already registers
  params: { _csrf_token: csrfToken }
})
```

The hook name must be exactly `TangoOAuth` (`Tango.Live.OAuthHook.hook_name/0`). Adjust the relative path if `app.js` lives elsewhere; it resolves from the JS file to the Mix `deps/` directory.

## Render the component

```heex
<.live_component
  module={Tango.Live.OAuthComponent}
  id="example-oauth"
  provider="example"
  tenant_id={@tenant_id}
  scopes={["accounts.read", "records.write"]}
  callback_url={@tango_callback_url}
  completion_origin={@completion_origin}
  on_connect="oauth_connected"
  on_error="oauth_error"
  button_class="btn btn-primary"
/>
```

Assign `@tenant_id` in `mount/3` from the authenticated scope. Compute `@completion_origin` from the endpoint (for example `MyAppWeb.Endpoint.url()`) and confirm it is listed in `allowed_completion_origins`. `Tango.Validation.origin/1` derives the `scheme://host[:port]` origin from a URL (default ports dropped, IPv6 bracketed, `nil` if unparsable), e.g. `Tango.Validation.origin(MyAppWeb.Endpoint.url())`.

| Assign                                         | Required | Notes                                                                    |
|------------------------------------------------|----------|--------------------------------------------------------------------------|
| `id`, `provider`, `tenant_id`                  | yes      | `provider` is the provider slug.                                         |
| `callback_url`                                 | yes      | Tango `/callback` URL registered with the provider.                      |
| `completion_origin`                            | yes      | Exact origin of the page hosting the button.                             |
| `scopes`                                       | no       | Defaults to provider `default_scopes`.                                   |
| `intent_reference`                             | no       | Defaults to a fresh random value per click.                              |
| `expected_connection_id`, `expected_subject`   | no       | Reauthorize an existing connection.                                      |
| `auth_params`                                  | no       | Extra provider authorization params.                                     |
| `button_class`, `button_label`, `inner_block`  | no       | Button styling and content. Default label: `Connect <Provider>`.         |
| `on_connect`, `on_error`                       | no       | Parent message names. Defaults: `"oauth_connected"`, `"oauth_error"`.    |

## Handle parent messages

The component uses `send(self(), ...)`, so the parent receives `handle_info/2` messages:

- `{on_connect, %{provider:, tenant_id:, completion_handle:, intent_reference:}}`
- `{on_error, %{error: category}}` where `category` is a stable atom or snake_case string, never a provider body.
- `{:tango_log, %{level:, message:, component_id:}}` progress events.

```elixir
@completion_keys [:provider, :tenant_id, :completion_handle, :intent_reference]

@impl true
def handle_info({"oauth_connected", %{completion_handle: handle, intent_reference: intent} = message}, socket) do
  # Reject any other key, such as a credential. Tenant comes from the socket.
  with true <- Enum.all?(Map.keys(message), &(&1 in @completion_keys)),
       {:ok, _connection, _link} <-
         MyApp.Integrations.complete(handle, intent, socket.assigns.tenant_id) do
    {:noreply, socket |> assign(:connected, true) |> put_flash(:info, "Connected.")}
  else
    _error -> {:noreply, put_flash(socket, :error, "Could not verify the connection.")}
  end
end

def handle_info({"oauth_error", %{error: _category}}, socket) do
  {:noreply, put_flash(socket, :error, "The connection was cancelled or failed.")}
end

def handle_info({:tango_log, _event}, socket), do: {:noreply, socket}
```

Add the `{:tango_log, _}` clause whenever the LiveView defines other `handle_info/2` clauses; otherwise the progress messages raise `FunctionClauseError` and crash the LiveView.

Do not trust `message.tenant_id`; use `socket.assigns.tenant_id`. Do not log the handle.

## What the hook enforces

The hook accepts a `message` event only when `event.source` is the popup it opened, `event.origin` equals the callback URL's origin, and `intent_reference` matches the pending intent. The component then accepts `oauth_complete` only with exactly `completion_handle` and `intent_reference`, and only for its pending intent; an `oauth_complete` or `oauth_error` whose `intent_reference` does not match the pending intent is ignored (pending state is kept, `on_error` is not fired), and a malformed `oauth_complete` becomes `on_error` with `:invalid_completion`. Closing the popup resets the button without sending `on_error`. If a popup blocker stops `window.open`, the hook sends nothing and the button stays in its "Connecting..." state until the component re-mounts.

## Test it

- Unit-test `complete/3` with a stub verifier module; the LiveView test only needs to `send(view.pid, {"oauth_connected", %{...}})` and assert the flash/assigns.
- Assert that a message containing `access_token` connects nothing.

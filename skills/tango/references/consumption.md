# One-time verified proofs (0.4.1)

Use staged consume mode for a point-in-time external-account link or organization administrator check that needs no durable Tango connection. Ordinary integrations that refresh credentials or import data stay on [connection completion](authorization.md). Verify the installed API and revised V04 schema first ([upgrading.md](upgrading.md#upgrade-to-041-and-revised-v04)); a version string or marker alone is insufficient.

## Start and verify

Use the configuration, exact origins, callback mount, and browser source/origin/intent checks in [authorization.md](authorization.md). Create the session on the authenticated server:

```elixir
{:ok, session} =
  Tango.create_authorization_session(provider_slug, tenant_id,
    completion_mode: :consume,
    scopes: ["records.read"],
    redirect_uri: "https://app.example.com/api/oauth/callback",
    completion_origin: "https://app.example.com",
    intent_reference: intent,
    expected_subject: known_subject
  )

{:ok, url} = Tango.Auth.authorization_url(session)
```

`intent`, provider, scopes, mode, verifier, and verifier options come from trusted server code. Store the initiating actor and pending operation with the intent. `expected_subject` may be omitted for account discovery or be a nonblank string independently of any connection. Consume sessions reject a non-nil `expected_connection_id` with `:invalid_completion_options`. The default mode is `:connection`; invalid modes return `:invalid_completion_mode`. Direct `Tango.create_session/3` rejects consume mode. Browser values, OAuth URL parameters, and token-response metadata cannot override the selected mode.

The callback exchanges the code once and stages encrypted access and refresh tokens alongside allowlisted plain metadata for at most ten minutes capped by session expiry. Consume mode still requires an access token; it is not a token-free OAuth exchange. Existing credential connections neither block consume mode nor get replaced.

Use the same `Tango.AuthorizationVerifier` contract as connection completion. The verifier receives `%{access_token:, granted_scopes:, provider_data:}` and returns `{:ok, %{subject: stable_id, claims: safe_claims, continuity: :initial}}`. Tango independently checks the session's optional expected subject. Make bounded, read-only provider calls before opening the host transaction. Select the verifier and its options on the server.

## Atomically link an account

`AccountVerifier` fetches the provider's account identity using the ephemeral access token, as in [the verifier example](authorization.md#4-write-a-verifier). All `MyApp` modules below are host-owned examples, not Tango APIs:

```elixir
with {:ok, _identity} <-
       Tango.verify_authorization(handle, tenant_id, {MyApp.AccountVerifier, []},
         provider: provider_slug,
         intent_reference: intent
       ) do
  Ecto.Multi.new()
  |> Tango.Authorization.multi_consume_authorization(:proof, handle, tenant_id,
    provider: provider_slug,
    intent_reference: intent,
    required_scopes: ["records.read"]
  )
  |> Ecto.Multi.run(:association, fn repo, %{proof: proof} ->
    MyApp.AccountLinks.insert_verified(repo, actor, intent, proof)
  end)
  |> MyApp.Repo.transaction()
end
```

`actor` comes from authentication and `tenant_id` from that actor's authorized server context. `AccountLinks.insert_verified/4` must lock the pending operation and recheck the actor's current permission, tenant, intent, cancellation, freshness, and any operation/version binding in this same transaction. Persist selected proof fields with the host association. Use the proof from the Multi step for writes; the earlier verification summary is not the committed result. Run the Multi on Tango's configured Repo and keep provider HTTP outside it.

The consume API belongs directly to `Tango.Authorization`; there is no `Tango.multi_consume_authorization/5` facade. It returns an `Ecto.Multi`, not a proof. Accepted options are required nonempty `:provider` and `:intent_reference`, plus optional `:required_scopes` (default `[]`, a list of valid nonblank scope strings). Other keys, including connection/refresh options, `completion_mode`, and `expected_subject`, return `:invalid_completion_options` even when nil or false. Bind mode/subject at session creation instead. Required scopes are API permissions, excluding protocol hints such as `offline_access` that providers omit from granted scopes.

The named step returns exactly five keys:

```elixir
%{
  provider: provider_slug,
  subject: verified_subject,
  claims: safe_claims,
  granted_scopes: granted_scopes,
  intent_reference: intent
}
```

No connection, credential, raw provider data, or handle is returned in that proof. `verify_authorization/4` still returns seven keys: these five plus `expected_connection_id` and `has_refresh_token`. With `:proof` as the name, transaction success is `{:ok, results}` with `results.proof`; consume failure is `{:error, :proof, reason, changes_so_far}`. A host failure uses that host step's name.

## Verify organization administrator membership

Identity or an organization ID alone does not establish administrator membership. This synthetic verifier checks an active administrator in one server-selected organization. Its host adapter makes a bounded, read-only provider request and normalizes the response to the shape below; implement the actual endpoint and scopes for the provider:

```elixir
defmodule MyApp.OrganizationAdminVerifier do
  @behaviour Tango.AuthorizationVerifier

  @impl true
  def verify(_provider, %{access_token: access_token}, opts) do
    organization_id = Keyword.fetch!(opts, :organization_id)
    client = Keyword.fetch!(opts, :client)

    with {:ok,
          %{
            "account_id" => subject,
            "organization_id" => ^organization_id,
            "state" => "active",
            "role" => "admin"
          }} <- client.fetch_membership(access_token, organization_id, opts),
         true <- is_binary(subject) and byte_size(subject) > 0 do
      {:ok,
       %{
         subject: subject,
         claims: %{"organization_id" => organization_id, "role" => "admin"},
         continuity: :initial
       }}
    else
      {:error, reason}
      when reason in [:network_error, :timeout, :temporarily_unavailable, :provider_unavailable] ->
        {:error, reason}

      _ -> {:error, :invalid_identity}
    end
  end
end

verifier =
  {MyApp.OrganizationAdminVerifier,
   client: MyApp.OrganizationClient, organization_id: organization_id}
```

Use this tuple in the account-link Multi pattern, replacing the host step with `MyApp.OrganizationOnboarding.insert_verified(repo, actor, intent, proof)`. That host function locks and revalidates the pending organization operation and actor permissions as above, including the expected organization. The client must sanitize errors to the documented atoms rather than return raw provider bodies. Reject inactive administrators, active non-administrators, organization mismatch, and malformed subjects. Provider-specific behavior stays in host code.

Verification proves only the checks the verifier performed at that moment. It does not prove fresh password entry, MFA, future membership, or continuing authorization. If the host requires fresher evidence after a delay or changed intent, restart verification or the flow under its own policy.

## Rollback, retries, and replay

After successful verification, consume in the host Multi. If a later host step fails, consumption and credential erasure roll back together; the verified candidate remains available until its normal expiry. Retry the consume Multi with the same handle and bindings after rechecking host state. Another verification call or code exchange is not required for this rollback retry. A repeated callback/code exchange does not recover the candidate; the session has already been exchanged. Calling the completion function above again does invoke its verifier again, so use a host retry path that rebuilds only the Multi when the verified candidate is still acceptable.

Concurrent attempts allow only one committed consumption. Replays return `:completion_consumed` while the candidate row remains, or `:invalid_completion` after cleanup deletes it. Neither result proves that the host operation failed; check the host's committed operation record before starting another flow. Wrong completion APIs return `:completion_mode_mismatch` without spending the candidate: consume cannot finalize a connection and connection mode cannot be consumed.

Only verifier errors `:network_error`, `:timeout`, `:temporarily_unavailable`, and `:provider_unavailable` preserve the handle for verification retry. Other verifier errors, malformed claims, and subject/continuity mismatch consume it. Completion errors include `:repo_mismatch`, `:invalid_completion_options`, `:invalid_scopes`, `:invalid_completion`, `:completion_mode_mismatch`, `:intent_mismatch`, `:client_changed`, `:completion_consumed`, `:expired_completion`, `:verification_required`, `:token_expired`, `:account_mismatch`, and `:missing_scopes`. Unknown/cross-tenant handles and inactive/wrong providers return `:invalid_completion`.

## Retention and cleanup

On committed consumption, candidate access/refresh token columns become NULL and `provider_data` becomes `%{}` in the same transaction as host writes. Safe identity fields remain until normal cleanup. No durable Tango connection, refresh credential, background import, or refresh workflow is created. Local erasure covers live application records, not backups/WAL or guaranteed memory zeroization, and does not revoke provider-side authorization. Run `Tango.cleanup_expired_authorizations/0` before `Tango.cleanup_expired_sessions/0` from the host scheduler.

Claims must be JSON-compatible, at most 4 KiB encoded, and free of token-like keys at every depth. Claims and allowlisted `provider_data` are plain metadata, so retain only reviewed non-secret identity fields. A key that lacks the word token can still contain a secret; filtering names is not a safety guarantee. Keep raw responses, credentials, headers, and handles out of host records, logs, browser payloads, and jobs. See [testing.md](testing.md#consume-mode-tests) for offline rollback, replay, and erasure checks.

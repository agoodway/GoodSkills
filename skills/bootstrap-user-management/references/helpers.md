# Display Helpers

## MemberDisplayHelpers

Create `lib/my_app_web/live/shared/member_display_helpers.ex`:

```elixir
defmodule MyAppWeb.Shared.MemberDisplayHelpers do
  @moduledoc """
  Shared display helpers for member management LiveViews.

  Centralises role and date formatting used by account user tables.
  """

  @doc """
  Returns a capitalised string label for a role atom.

  ## Examples

      iex> format_role(:owner)
      "Owner"

      iex> format_role(:member)
      "Member"
  """
  @spec format_role(atom()) :: String.t()
  def format_role(role) when is_atom(role), do: role |> Atom.to_string() |> String.capitalize()

  @doc """
  Formats a `NaiveDateTime`, `DateTime`, or `Date` as a `"YYYY-MM-DD"` string.
  """
  @spec format_date(NaiveDateTime.t() | DateTime.t() | Date.t()) :: String.t()
  def format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  def format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d")
  def format_date(%Date{} = d), do: Calendar.strftime(d, "%Y-%m-%d")
end
```

defmodule Defdo.KoeFrame.Migrator do
  @moduledoc """
  Versioned migrator for KoeFrame-owned application data.

  Tenant and Vault structures are installed by the app-local wrapper migration
  into the same schema. This migrator owns only KoeFrame tables.
  """

  use Defdo.Migrator,
    control_table: "koe_frame",
    prefix: Defdo.KoeFrame.RepoConfig.schema(),
    current_version: 2
end

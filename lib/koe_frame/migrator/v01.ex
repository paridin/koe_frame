defmodule Defdo.KoeFrame.Migrator.V01 do
  @moduledoc false

  use Defdo.Migrator.Migration, version: 1
  import Defdo.Tenant.Migration

  def up(%{prefix: prefix}) do
    create table(:koe_frame_integrations, primary_key: false, prefix: prefix) do
      add :id, :binary_id, primary_key: true
      tenant_id()
      add :provider, :string, null: false
      add :endpoint_url, :string, null: false
      add :credential_ref, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:koe_frame_integrations, [:tenant_id, :provider],
             name: :koe_frame_integrations_tenant_provider_index,
             prefix: prefix
           )

    create constraint(:koe_frame_integrations, :koe_frame_integrations_provider_check,
             check: "provider IN ('sonarr', 'jellyfin')",
             prefix: prefix
           )
  end

  def down(%{prefix: prefix}) do
    drop constraint(:koe_frame_integrations, :koe_frame_integrations_provider_check,
           prefix: prefix
         )

    drop index(:koe_frame_integrations, [:tenant_id, :provider],
           name: :koe_frame_integrations_tenant_provider_index,
           prefix: prefix
         )

    drop table(:koe_frame_integrations, prefix: prefix)
  end
end

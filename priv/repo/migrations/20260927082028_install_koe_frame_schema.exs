defmodule Defdo.KoeFrame.Repo.Migrations.InstallKoeFrameSchema do
  use Ecto.Migration

  @disable_ddl_transaction true
  @prefix "defdo_koe_frame"

  def up do
    Defdo.Tenant.Migrator.up(version: 7, prefix: @prefix)
    Defdo.Vault.Migrator.up(version: 13, prefix: @prefix)
    Oban.Migrations.up(version: 14, prefix: @prefix)
    Defdo.Order.Migrations.up(version: 4, prefix: @prefix)
    Defdo.KoeFrame.Migrator.up(version: 1, prefix: @prefix)
  end

  def down do
    Defdo.KoeFrame.Migrator.down(version: 1, prefix: @prefix)
    Defdo.Order.Migrations.down(version: 1, prefix: @prefix)
    Oban.Migrations.down(version: 1, prefix: @prefix)
    Defdo.Vault.Migrator.down(version: 1, prefix: @prefix)
    Defdo.Tenant.Migrator.down(version: 1, prefix: @prefix)
  end
end

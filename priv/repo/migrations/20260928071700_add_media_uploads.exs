defmodule Defdo.KoeFrame.Repo.Migrations.AddMediaUploads do
  use Ecto.Migration

  @prefix "defdo_koe_frame"

  def up do
    Defdo.KoeFrame.Migrator.up(version: 2, prefix: @prefix)
  end

  def down do
    Defdo.KoeFrame.Migrator.down(version: 2, prefix: @prefix)
  end
end

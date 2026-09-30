defmodule Defdo.KoeFrame.Migrator.V02 do
  @moduledoc false

  use Defdo.Migrator.Migration, version: 2
  import Defdo.Tenant.Migration

  def up(%{prefix: prefix}) do
    create table(:koe_frame_media_uploads, primary_key: false, prefix: prefix) do
      add :id, :binary_id, primary_key: true
      tenant_id()
      add :intake_id, :binary_id, null: false
      add :relative_path, :string, null: false
      add :upload_length, :bigint, null: false
      add :upload_offset, :bigint, null: false, default: 0
      add :expected_sha256, :string, null: false
      add :status, :string, null: false, default: "uploading"
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(
             :koe_frame_media_uploads,
             [:tenant_id, :intake_id, :relative_path],
             name: :koe_frame_media_uploads_tenant_intake_path_uidx,
             prefix: prefix
           )

    create index(:koe_frame_media_uploads, [:tenant_id, :intake_id, :status],
             name: :koe_frame_media_uploads_tenant_intake_state_idx,
             prefix: prefix
           )

    create constraint(:koe_frame_media_uploads, :koe_frame_media_uploads_length_check,
             check:
               "upload_length >= 0 AND upload_offset >= 0 AND upload_offset <= upload_length",
             prefix: prefix
           )

    create constraint(:koe_frame_media_uploads, :koe_frame_media_uploads_sha256_check,
             check: "expected_sha256 ~ '^[0-9a-f]{64}$'",
             prefix: prefix
           )

    create constraint(:koe_frame_media_uploads, :koe_frame_media_uploads_status_check,
             check: "status IN ('uploading', 'staged', 'checksum_mismatch')",
             prefix: prefix
           )
  end

  def down(%{prefix: prefix}) do
    execute("LOCK TABLE #{prefix}.koe_frame_media_uploads IN ACCESS EXCLUSIVE MODE")

    execute("""
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM #{prefix}.koe_frame_media_uploads LIMIT 1) THEN
        RAISE EXCEPTION 'refusing to remove KoeFrame media upload records while rows exist';
      END IF;
    END $$;
    """)

    drop constraint(:koe_frame_media_uploads, :koe_frame_media_uploads_status_check,
           prefix: prefix
         )

    drop constraint(:koe_frame_media_uploads, :koe_frame_media_uploads_sha256_check,
           prefix: prefix
         )

    drop constraint(:koe_frame_media_uploads, :koe_frame_media_uploads_length_check,
           prefix: prefix
         )

    drop index(:koe_frame_media_uploads, [:tenant_id, :intake_id, :status],
           name: :koe_frame_media_uploads_tenant_intake_state_idx,
           prefix: prefix
         )

    drop index(:koe_frame_media_uploads, [:tenant_id, :intake_id, :relative_path],
           name: :koe_frame_media_uploads_tenant_intake_path_uidx,
           prefix: prefix
         )

    drop table(:koe_frame_media_uploads, prefix: prefix)
  end
end

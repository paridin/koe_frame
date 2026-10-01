defmodule Defdo.KoeFrame.MediaIntake.Upload do
  @moduledoc """
  Tenant-owned resumable upload record for one file in a local media intake.

  `relative_path` preserves the selected directory layout under the generated
  intake ID. It is validated before storage and never chooses a library path.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Defdo.KoeFrame.MediaIntake.RelativePath
  alias Defdo.Tenant.Context

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "koe_frame_media_uploads" do
    field :tenant_id, :binary_id
    field :intake_id, :binary_id
    field :relative_path, :string
    field :upload_length, :integer
    field :upload_offset, :integer, default: 0
    field :expected_sha256, :string

    field :status, Ecto.Enum,
      values: [:uploading, :staged, :checksum_mismatch],
      default: :uploading

    timestamps(type: :utc_datetime_usec)
  end

  @cast_fields [:intake_id, :relative_path, :upload_length, :expected_sha256]
  @default_max_upload_bytes 250 * 1024 * 1024 * 1024

  def changeset(upload, attrs) do
    upload
    |> cast(attrs, @cast_fields)
    |> put_change(:tenant_id, Context.tenant_id())
    |> put_change(:upload_offset, 0)
    |> put_change(:status, :uploading)
    |> validate_required([
      :tenant_id,
      :intake_id,
      :relative_path,
      :upload_length,
      :expected_sha256
    ])
    |> validate_number(:upload_length, greater_than_or_equal_to: 0)
    |> validate_number(:upload_length,
      less_than_or_equal_to:
        Application.get_env(
          :koe_frame,
          :media_max_upload_bytes,
          @default_max_upload_bytes
        ),
      message: "exceeds the configured maximum upload size"
    )
    |> validate_sha256()
    |> validate_relative_path()
    |> unique_constraint([:tenant_id, :intake_id, :relative_path],
      name: :koe_frame_media_uploads_tenant_intake_path_uidx
    )
  end

  defp validate_sha256(changeset) do
    validate_change(changeset, :expected_sha256, fn :expected_sha256, digest ->
      if Regex.match?(~r/\A[0-9a-f]{64}\z/, digest),
        do: [],
        else: [expected_sha256: "must be a lowercase SHA-256 hex digest"]
    end)
  end

  defp validate_relative_path(changeset) do
    validate_change(changeset, :relative_path, fn :relative_path, path ->
      case RelativePath.validate(path) do
        {:ok, ^path} -> []
        {:error, _reason} -> [relative_path: "must be a safe path relative to the intake root"]
      end
    end)
  end
end

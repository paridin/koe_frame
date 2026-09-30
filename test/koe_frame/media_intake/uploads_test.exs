defmodule Defdo.KoeFrame.MediaIntake.UploadsTest do
  use Defdo.KoeFrame.DataCase, async: false

  import Bitwise, only: [band: 2]

  alias Defdo.KoeFrame.MediaIntake.{RelativePath, Staging, Upload, Uploads}
  alias Defdo.Tenant.Context

  setup do
    previous_context = Context.get()
    previous_root = Application.fetch_env(:koe_frame, :media_staging_root)
    previous_owner = Application.fetch_env(:koe_frame, :media_staging_owner)

    root_parent =
      Path.join(
        System.user_home!(),
        ".koe-frame-upload-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root_parent)
    File.chmod!(root_parent, 0o700)
    root = Path.join(root_parent, "staging")

    Application.put_env(:koe_frame, :media_staging_root, root)

    tenant = tenant_fixture!("upload-a")
    Context.put(Context.new(tenant.tenant_id))

    on_exit(fn ->
      File.rm_rf(root_parent)

      case previous_root do
        {:ok, value} -> Application.put_env(:koe_frame, :media_staging_root, value)
        :error -> Application.delete_env(:koe_frame, :media_staging_root)
      end

      case previous_owner do
        {:ok, value} -> Application.put_env(:koe_frame, :media_staging_owner, value)
        :error -> Application.delete_env(:koe_frame, :media_staging_owner)
      end

      case previous_context do
        nil -> Context.clear()
        context -> Context.put(context)
      end
    end)

    {:ok, tenant: tenant}
  end

  test "refuses an unprovisioned existing staging root without changing its mode", %{
    tenant: tenant
  } do
    root = Application.fetch_env!(:koe_frame, :media_staging_root)
    File.mkdir_p!(root)
    File.chmod!(root, 0o755)

    upload = %Upload{
      tenant_id: tenant.tenant_id,
      id: Ecto.UUID.generate(),
      upload_offset: 0
    }

    assert {:error, :unsafe_staging_root} = Staging.prepare_session(upload)
    assert {:ok, %{mode: mode}} = File.lstat(root)
    assert band(mode, 0o777) == 0o755
  end

  test "retries an upload creation idempotently and resumes from the committed offset" do
    bytes = "anime video bytes"
    intake_id = Ecto.UUID.generate()
    attrs = upload_attrs(intake_id, "Sep 26/Season 01/episode.mkv", bytes)

    assert {:ok, upload} = Uploads.create_upload(attrs)
    assert {:ok, same_upload} = Uploads.create_upload(attrs)
    assert same_upload.id == upload.id

    assert {:ok, after_first_chunk} = Uploads.append_chunk(upload.id, 0, "anime ")
    assert after_first_chunk.upload_offset == 6

    assert {:error, {:offset_mismatch, 6}} = Uploads.append_chunk(upload.id, 0, "anime ")

    assert {:ok, after_resume} = Uploads.append_chunk(upload.id, 6, "video bytes")
    assert after_resume.upload_offset == byte_size(bytes)

    assert {:ok, staged} = Uploads.finalize_upload(upload.id)
    assert staged.status == :staged
    assert {:ok, path} = Staging.staged_path(staged)
    assert File.read!(path) == bytes
    assert {:ok, stat} = File.stat(path)
    assert band(stat.mode, 0o777) == 0o640
    assert band(File.stat!(Path.dirname(path)).mode, 0o777) == 0o750
  end

  test "casts a string upload length before checking creation idempotency" do
    bytes = "anime media bytes"
    attrs = upload_attrs(Ecto.UUID.generate(), "Season 01/episode.mkv", bytes)
    attrs_with_string_length = Map.update!(attrs, :upload_length, &Integer.to_string/1)

    assert {:ok, upload} = Uploads.create_upload(attrs_with_string_length)
    assert upload.upload_length == byte_size(bytes)
    assert {:ok, retry} = Uploads.create_upload(attrs_with_string_length)
    assert retry.id == upload.id
    assert {:ok, numeric_retry} = Uploads.create_upload(attrs)
    assert numeric_retry.id == upload.id
  end

  test "requires a stable intake ID so a client can safely retry creation" do
    attrs = upload_attrs(nil, "episode.mkv", "payload")

    assert {:error, {:invalid_upload, changeset}} = Uploads.create_upload(attrs)
    assert %{intake_id: [_message]} = errors_on(changeset)
  end

  test "rejects unsafe relative paths before creating a staging object" do
    assert {:error, {:invalid_upload, changeset}} =
             Uploads.create_upload(upload_attrs(Ecto.UUID.generate(), "../outside.mkv", "x"))

    assert %{relative_path: [_message]} = errors_on(changeset)
    assert {:error, :invalid_relative_path} = RelativePath.validate("/etc/passwd")
    assert {:error, :invalid_relative_path} = RelativePath.validate("Season 01/../../outside.mkv")
    assert {:error, :invalid_relative_path} = RelativePath.validate("Season 01\\episode.mkv")
  end

  test "marks a completed upload whose whole-file digest does not match" do
    bytes = "different bytes"

    attrs =
      upload_attrs(Ecto.UUID.generate(), "Season 01/episode.mkv", bytes)
      |> Map.put(:expected_sha256, String.duplicate("0", 64))

    assert {:ok, upload} = Uploads.create_upload(attrs)
    assert {:ok, %{upload_offset: offset}} = Uploads.append_chunk(upload.id, 0, bytes)
    assert offset == byte_size(bytes)
    assert {:error, :checksum_mismatch} = Uploads.finalize_upload(upload.id)
    assert {:ok, %{status: :checksum_mismatch}} = Uploads.get_upload(upload.id)
  end

  test "a retry checks that an already staged object is still present and intact" do
    bytes = "recoverable payload"
    attrs = upload_attrs(Ecto.UUID.generate(), "episode.mkv", bytes)

    assert {:ok, upload} = Uploads.create_upload(attrs)
    assert {:ok, _upload} = Uploads.append_chunk(upload.id, 0, bytes)
    assert {:ok, staged} = Uploads.finalize_upload(upload.id)
    assert {:ok, path} = Staging.staged_path(staged)

    assert :ok = File.rm(path)

    assert {:error, {:staged_file_check_failed, :staged_file_missing}} =
             Uploads.finalize_upload(staged.id)
  end

  test "staged verification rejects a symlinked parent directory" do
    bytes = "external payload"
    attrs = upload_attrs(Ecto.UUID.generate(), "Season 01/episode.mkv", bytes)

    assert {:ok, upload} = Uploads.create_upload(attrs)
    assert {:ok, _upload} = Uploads.append_chunk(upload.id, 0, bytes)
    assert {:ok, staged} = Uploads.finalize_upload(upload.id)
    assert {:ok, path} = Staging.staged_path(staged)

    linked_parent = Path.dirname(path)
    external_parent = linked_parent <> "-external"
    File.rm_rf!(external_parent)
    on_exit(fn -> File.rm_rf(external_parent) end)
    File.rm!(path)
    File.rm_rf!(linked_parent)
    File.mkdir_p!(external_parent)
    File.write!(Path.join(external_parent, "episode.mkv"), bytes)
    File.ln_s!(external_parent, linked_parent)

    assert {:error, :unsafe_staged_directory} = Staging.verify_staged(staged)
    refute File.exists?(Path.join(external_parent, "other.mkv"))
  end

  test "applies the configured staging owner and group" do
    parent_stat = File.stat!(File.cwd!())
    owner = {parent_stat.uid, parent_stat.gid}
    Application.put_env(:koe_frame, :media_staging_owner, owner)

    bytes = "owner and group"

    assert {:ok, upload} =
             Uploads.create_upload(upload_attrs(Ecto.UUID.generate(), "episode.mkv", bytes))

    assert {:ok, _upload} = Uploads.append_chunk(upload.id, 0, bytes)
    assert {:ok, staged} = Uploads.finalize_upload(upload.id)
    assert {:ok, path} = Staging.staged_path(staged)
    stat = File.stat!(path)
    parent_stat = File.stat!(Path.dirname(path))

    assert {stat.uid, stat.gid} == owner
    assert band(stat.mode, 0o777) == 0o640
    assert parent_stat.uid == File.stat!(File.cwd!()).uid
    assert parent_stat.gid == elem(owner, 1)
    assert band(parent_stat.mode, 0o777) == 0o750
  end

  test "writes use process tenant and another tenant cannot discover the upload", %{
    tenant: tenant
  } do
    bytes = "private bytes"
    intake_id = Ecto.UUID.generate()
    other_tenant = tenant_fixture!("upload-b")

    attrs =
      upload_attrs(intake_id, "episode.mkv", bytes)
      |> Map.put(:tenant_id, other_tenant.tenant_id)

    assert {:ok, upload} = Uploads.create_upload(attrs)
    assert upload.tenant_id == tenant.tenant_id

    Context.put(Context.new(other_tenant.tenant_id))

    assert {:ok, nil} = Uploads.get_upload(upload.id)
    assert {:ok, []} = Uploads.list_intake_uploads(intake_id)
  end

  test "fails closed when the tenant edge has not established context" do
    Context.clear()

    assert {:error, :missing_tenant_context} =
             Uploads.create_upload(upload_attrs(Ecto.UUID.generate(), "episode.mkv", "bytes"))
  end

  defp upload_attrs(intake_id, relative_path, bytes) do
    %{
      intake_id: intake_id,
      relative_path: relative_path,
      upload_length: byte_size(bytes),
      expected_sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    }
  end

  defp tenant_fixture!(suffix) do
    {:ok, tenant} =
      Defdo.Tenant.create_profile(%{
        name: "KoeFrame #{suffix} #{System.unique_integer([:positive])}",
        region: "mx",
        code: "koe-#{suffix}-#{System.unique_integer([:positive])}",
        logo_url: "https://example.test/logo.png",
        domain: "#{suffix}-#{System.unique_integer([:positive])}.example.test",
        allowed_domains: ["example.test"],
        is_active: false,
        is_deleted: false,
        tier: "starter"
      })

    tenant
  end
end

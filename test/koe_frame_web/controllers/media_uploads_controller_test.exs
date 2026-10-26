defmodule Defdo.KoeFrameWeb.MediaUploadsControllerTest do
  use Defdo.KoeFrameWeb.ConnCase, async: false

  alias Defdo.KoeFrame.MediaIntake.{Upload, Uploads}
  alias Defdo.KoeFrame.Repo
  alias Defdo.Tenant.Context

  @scope "koe_frame:media:write"
  @credential "test-media-credential"
  @tus_version "1.0.0"
  @max_chunk_bytes 8 * 1024 * 1024

  setup do
    previous_context = Context.get()
    previous_introspector = Application.get_env(:koe_frame, :media_credential_introspector)
    previous_result = Application.get_env(:koe_frame, :media_credential_test_result)
    previous_owner = Application.get_env(:koe_frame, :media_credential_test_owner)
    previous_root = Application.get_env(:koe_frame, :media_staging_root)
    previous_staging_owner = Application.get_env(:koe_frame, :media_staging_owner)

    tenant = tenant_fixture!("media-http")

    root_parent =
      Path.join(System.user_home!(), "koe-frame-http-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root_parent)
    File.chmod!(root_parent, 0o700)
    owner_stat = File.stat!(root_parent)

    Application.put_env(:koe_frame, :media_staging_root, Path.join(root_parent, "staging"))
    Application.put_env(:koe_frame, :media_staging_owner, {owner_stat.uid, owner_stat.gid})

    Application.put_env(
      :koe_frame,
      :media_credential_introspector,
      Defdo.KoeFrameWeb.MediaUploadsControllerTest.FakeIntrospector
    )

    Application.put_env(:koe_frame, :media_credential_test_owner, self())
    set_identity(tenant.tenant_id)
    Context.clear()

    on_exit(fn ->
      File.rm_rf(root_parent)
      restore_env(:media_credential_introspector, previous_introspector)
      restore_env(:media_credential_test_result, previous_result)
      restore_env(:media_credential_test_owner, previous_owner)
      restore_env(:media_staging_root, previous_root)
      restore_env(:media_staging_owner, previous_staging_owner)
      restore_context(previous_context)
    end)

    {:ok, tenant: tenant}
  end

  test "advertises Tus capabilities for an authenticated media credential" do
    conn =
      build_conn()
      |> authorize()
      |> options("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads")

    assert conn.status == 204
    assert get_resp_header(conn, "tus-version") == [@tus_version]
    assert get_resp_header(conn, "tus-extension") == ["creation"]
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert_received {:media_credential_seen, @credential}
  end

  test "creates, resumes, inspects, and finalizes an authenticated Tus upload", %{tenant: tenant} do
    bytes = "anime episode bytes"
    intake_id = Ecto.UUID.generate()
    digest = sha256(bytes)

    conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("upload-length", Integer.to_string(byte_size(bytes)))
      |> put_req_header("upload-metadata", metadata("Season 01/episode.mkv", digest))
      |> post("/api/v1/media/intakes/#{intake_id}/uploads", %{})

    assert conn.status == 201
    assert get_resp_header(conn, "tus-resumable") == [@tus_version]
    assert get_resp_header(conn, "upload-offset") == ["0"]
    assert get_resp_header(conn, "upload-length") == [Integer.to_string(byte_size(bytes))]
    assert [location] = get_resp_header(conn, "location")
    assert_received {:media_credential_seen, @credential}
    assert Context.get() == nil

    upload_id = location |> String.split("/") |> List.last()

    assert {:ok, upload} =
             Context.with_context(tenant.tenant_id, fn -> Uploads.get_upload(upload_id) end)

    assert upload.tenant_id == tenant.tenant_id

    head_conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> head(location)

    assert head_conn.status == 200
    assert get_resp_header(head_conn, "upload-offset") == ["0"]
    assert get_resp_header(head_conn, "cache-control") == ["no-store"]
    assert Context.get() == nil

    patch_conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("content-type", "application/offset+octet-stream")
      |> put_req_header("upload-offset", "0")
      |> patch(location, bytes)

    assert patch_conn.status == 204
    assert get_resp_header(patch_conn, "upload-offset") == [Integer.to_string(byte_size(bytes))]
    assert Context.get() == nil

    finalize_conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post(location <> "/finalize", %{})

    assert finalize_conn.status == 200
    assert %{"id" => ^upload_id, "status" => "staged"} = json_response(finalize_conn, 200)
    assert Context.get() == nil
  end

  test "rejects absent, inactive, and malformed credentials before touching uploads" do
    absent =
      build_conn()
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(absent, 401) == %{"errors" => %{"code" => "unauthorized"}}
    refute_received {:media_credential_seen, _credential}

    malformed_header =
      build_conn()
      |> put_req_header("authorization", "Basic not-a-bearer")
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(malformed_header, 401) == %{
             "errors" => %{"code" => "unauthorized"}
           }

    refute_received {:media_credential_seen, _credential}

    duplicate_headers =
      build_conn()
      |> put_req_header("authorization", "Bearer first")
      |> Map.update!(:req_headers, fn headers ->
        headers ++ [{"authorization", "Bearer second"}]
      end)
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(duplicate_headers, 401) == %{
             "errors" => %{"code" => "unauthorized"}
           }

    refute_received {:media_credential_seen, _credential}

    set_identity(nil)

    inactive =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(inactive, 401) == %{"errors" => %{"code" => "unauthorized"}}

    Application.put_env(:koe_frame, :media_credential_test_result, {:ok, %{"active" => true}})

    malformed =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(malformed, 401) == %{"errors" => %{"code" => "unauthorized"}}
    assert Context.get() == nil
  end

  test "rejects malformed tenant identity from introspection" do
    Application.put_env(
      :koe_frame,
      :media_credential_test_result,
      {:ok,
       %{
         "active" => true,
         "scopes" => [@scope],
         "tenant" => %{"id" => "not-a-uuid"}
       }}
    )

    conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(conn, 401) == %{"errors" => %{"code" => "unauthorized"}}
    assert Context.get() == nil
  end

  test "requires exact media scope and maps introspection outage to 503", %{tenant: tenant} do
    Application.put_env(
      :koe_frame,
      :media_credential_test_result,
      {:ok,
       %{
         "active" => true,
         "scopes" => ["#{@scope}:admin"],
         "tenant" => %{"id" => tenant.tenant_id}
       }}
    )

    forbidden =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(forbidden, 403) == %{"errors" => %{"code" => "insufficient_scope"}}

    Application.put_env(:koe_frame, :media_credential_test_result, {:error, :transport})

    unavailable =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(unavailable, 503) == %{
             "errors" => %{"code" => "authentication_unavailable"}
           }

    assert Context.get() == nil
  end

  test "conceals uploads owned by another tenant", %{tenant: tenant} do
    bytes = "private episode"
    intake_id = Ecto.UUID.generate()
    attrs = upload_attrs(intake_id, "episode.mkv", bytes)

    assert {:ok, upload} =
             Context.with_context(tenant.tenant_id, fn -> Uploads.create_upload(attrs) end)

    other_tenant = tenant_fixture!("media-http-other")
    set_identity(other_tenant.tenant_id)

    conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> head("/api/v1/media/uploads/#{upload.id}")

    assert conn.status == 404
    assert Context.get() == nil
  end

  test "rejects malformed metadata and unsupported Tus versions before session creation", %{
    tenant: tenant
  } do
    no_version =
      build_conn()
      |> authorize()
      |> put_req_header("upload-length", "4")
      |> put_req_header("upload-metadata", metadata("episode.mkv", sha256("data")))
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(no_version, 412) == %{"errors" => %{"code" => "unsupported_tus_version"}}

    invalid_metadata =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("upload-length", "4")
      |> put_req_header("upload-metadata", "relative_path !!!,sha256 invalid")
      |> post("/api/v1/media/intakes/#{Ecto.UUID.generate()}/uploads", %{})

    assert json_response(invalid_metadata, 400) == %{
             "errors" => %{"code" => "invalid_upload_metadata"}
           }

    assert Context.with_context(tenant.tenant_id, fn -> Repo.aggregate(Upload, :count) end) == 0
  end

  test "rejects oversized chunk before advancing committed offset", %{tenant: tenant} do
    bytes = "payload"
    upload = create_upload!(tenant, bytes)

    conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("content-type", "application/offset+octet-stream")
      |> put_req_header("upload-offset", "0")
      |> patch("/api/v1/media/uploads/#{upload.id}", String.duplicate("x", @max_chunk_bytes + 1))

    assert json_response(conn, 413) == %{"errors" => %{"code" => "chunk_too_large"}}

    assert {:ok, %{upload_offset: 0}} =
             Context.with_context(tenant.tenant_id, fn -> Uploads.get_upload(upload.id) end)

    exceeds_length =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("content-type", "application/offset+octet-stream")
      |> put_req_header("upload-offset", "0")
      |> patch("/api/v1/media/uploads/#{upload.id}", "12345678")

    assert json_response(exceeds_length, 413) == %{
             "errors" => %{"code" => "chunk_exceeds_upload_length"}
           }

    assert {:ok, %{upload_offset: 0}} =
             Context.with_context(tenant.tenant_id, fn -> Uploads.get_upload(upload.id) end)
  end

  test "returns current offset on conflict and checksum mismatch on explicit finalize", %{
    tenant: tenant
  } do
    bytes = "verified payload"
    wrong_digest = String.duplicate("0", 64)
    upload = create_upload!(tenant, bytes, wrong_digest)

    conflict =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("content-type", "application/offset+octet-stream")
      |> put_req_header("upload-offset", "1")
      |> patch("/api/v1/media/uploads/#{upload.id}", bytes)

    assert json_response(conflict, 409) == %{"errors" => %{"code" => "offset_mismatch"}}
    assert get_resp_header(conflict, "upload-offset") == ["0"]

    patch_conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> put_req_header("content-type", "application/offset+octet-stream")
      |> put_req_header("upload-offset", "0")
      |> patch("/api/v1/media/uploads/#{upload.id}", bytes)

    assert patch_conn.status == 204

    finalize_conn =
      build_conn()
      |> authorize()
      |> tus_headers()
      |> post("/api/v1/media/uploads/#{upload.id}/finalize", %{})

    assert json_response(finalize_conn, 422) == %{"errors" => %{"code" => "checksum_mismatch"}}

    assert {:ok, %{status: :checksum_mismatch}} =
             Context.with_context(tenant.tenant_id, fn -> Uploads.get_upload(upload.id) end)
  end

  defp authorize(conn) do
    put_req_header(conn, "authorization", "Bearer " <> @credential)
  end

  defp tus_headers(conn), do: put_req_header(conn, "tus-resumable", @tus_version)

  defp metadata(relative_path, digest) do
    "relative_path #{Base.encode64(relative_path)},sha256 #{Base.encode64(digest)}"
  end

  defp create_upload!(tenant, bytes, digest \\ nil) do
    attrs = upload_attrs(Ecto.UUID.generate(), "episode.mkv", bytes)
    attrs = if digest, do: Map.put(attrs, :expected_sha256, digest), else: attrs
    {:ok, upload} = Context.with_context(tenant.tenant_id, fn -> Uploads.create_upload(attrs) end)
    upload
  end

  defp upload_attrs(intake_id, relative_path, bytes) do
    %{
      intake_id: intake_id,
      relative_path: relative_path,
      upload_length: byte_size(bytes),
      expected_sha256: sha256(bytes)
    }
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp set_identity(tenant_id) do
    info =
      if tenant_id do
        %{"active" => true, "scopes" => [@scope], "tenant" => %{"id" => tenant_id}}
      else
        %{"active" => false}
      end

    Application.put_env(:koe_frame, :media_credential_test_result, {:ok, info})
  end

  defp restore_env(key, nil), do: Application.delete_env(:koe_frame, key)
  defp restore_env(key, value), do: Application.put_env(:koe_frame, key, value)

  defp restore_context(nil), do: Context.clear()
  defp restore_context(context), do: Context.put(context)

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

defmodule Defdo.KoeFrameWeb.MediaUploadsControllerTest.FakeIntrospector do
  @moduledoc false

  def introspect_credential(credential) do
    send(
      Application.fetch_env!(:koe_frame, :media_credential_test_owner),
      {:media_credential_seen, credential}
    )

    Application.fetch_env!(:koe_frame, :media_credential_test_result)
  end
end

defmodule Defdo.KoeFrame.MediaIntake.FilesystemAdapterTest do
  use ExUnit.Case, async: true

  import Bitwise, only: [band: 2]

  alias Defdo.KoeFrame.MediaIntake.{FilesystemAdapter, PathSafety}

  test "storage roots cannot be a filesystem root or shared temporary directory" do
    assert {:error, :unsafe_staging_root} = PathSafety.validate_root_parent("/")
    assert {:error, :unsafe_staging_root} = PathSafety.validate_root_parent("/tmp")
  end

  test "accepts a dedicated directory with safe permissions" do
    root =
      Path.join(
        System.user_home!(),
        ".koe-frame-safe-root-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    File.chmod!(root, 0o750)
    on_exit(fn -> File.rm_rf!(root) end)

    assert :ok = PathSafety.validate_root_parent(root)
  end

  test "rejects an existing staging root with group/world write or sticky permissions" do
    root =
      Path.join(
        System.user_home!(),
        ".koe-frame-unsafe-root-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)

    on_exit(fn ->
      File.chmod!(root, 0o700)
      File.rm_rf!(root)
    end)

    File.chmod!(root, 0o770)
    assert {:error, :unsafe_staging_root} = PathSafety.validate_root_parent(root)

    File.chmod!(root, 0o1770)
    assert {:error, :unsafe_staging_root} = PathSafety.validate_root_parent(root)
  end

  test "rejects a symlink as the configured staging root" do
    target =
      Path.join(
        System.user_home!(),
        ".koe-frame-root-target-#{System.unique_integer([:positive])}"
      )

    link = target <> "-link"
    File.mkdir_p!(target)
    File.chmod!(target, 0o750)
    File.ln_s!(target, link)

    on_exit(fn ->
      File.rm(link)
      File.rm_rf!(target)
    end)

    assert {:error, :unsafe_staging_root} = PathSafety.validate_root_parent(link)
  end

  test "does not chmod an existing root that was not provisioned for staging" do
    root =
      Path.join(
        System.user_home!(),
        ".koe-frame-unprepared-root-#{System.unique_integer([:positive])}"
      )

    source = root <> "-source.mkv"
    File.mkdir_p!(root)
    File.chmod!(root, 0o755)
    File.write!(source, "private media bytes")

    on_exit(fn ->
      File.chmod!(root, 0o700)
      File.rm_rf!(root)
      File.rm(source)
    end)

    digest =
      :crypto.hash(:sha256, "private media bytes")
      |> Base.encode16(case: :lower)

    assert {:error, :unsafe_filesystem_root} =
             FilesystemAdapter.upload(
               source,
               "tenant/intake/episode.mkv",
               %{root: root, owner: nil, file_mode: 0o640, directory_mode: 0o750},
               expected_sha256: digest
             )

    assert {:ok, %{mode: mode}} = File.lstat(root)
    assert band(mode, 0o777) == 0o755
  end

  test "publishing rejects a symlinked parent instead of escaping the media root" do
    root =
      Path.join(
        System.user_home!(),
        ".koe-frame-media-root-#{System.unique_integer([:positive])}"
      )

    external = root <> "-external"
    source = root <> "-source.mkv"
    File.mkdir_p!(root)
    File.chmod!(root, 0o750)
    File.mkdir_p!(external)
    File.write!(source, "private media bytes")
    File.ln_s!(external, Path.join(root, "tenant"))

    on_exit(fn ->
      File.rm_rf(root)
      File.rm_rf(external)
      File.rm(source)
    end)

    digest =
      :crypto.hash(:sha256, "private media bytes")
      |> Base.encode16(case: :lower)

    assert {:error, :unsafe_staged_directory} =
             FilesystemAdapter.upload(
               source,
               "tenant/intake/episode.mkv",
               %{root: root, owner: nil, file_mode: 0o640, directory_mode: 0o750},
               expected_sha256: digest
             )

    refute File.exists?(Path.join(external, "intake/episode.mkv"))
  end

  test "checksum mismatch does not create directories for an untrusted object key" do
    root =
      Path.join(
        System.user_home!(),
        ".koe-frame-checksum-root-#{System.unique_integer([:positive])}"
      )

    source = root <> "-source.mkv"
    tenant_id = Ecto.UUID.generate()
    intake_id = Ecto.UUID.generate()

    File.write!(source, "private media bytes")

    on_exit(fn ->
      File.rm_rf!(root)
      File.rm(source)
    end)

    object_key = Path.join([tenant_id, intake_id, "Season 01/Disc 01/episode.mkv"])

    assert {:error, :checksum_mismatch} =
             FilesystemAdapter.upload(
               source,
               object_key,
               %{root: root, owner: nil, file_mode: 0o640, directory_mode: 0o750},
               expected_sha256: String.duplicate("0", 64)
             )

    refute File.dir?(Path.join(root, tenant_id))
  end

  test "publishing rejects a storage root beneath a group-writable parent" do
    parent =
      Path.join(
        System.user_home!(),
        "koe-frame-unsafe-parent-#{System.unique_integer([:positive])}"
      )

    root = Path.join(parent, "media")
    source = parent <> "-source.mkv"
    File.mkdir_p!(parent)
    File.chmod!(parent, 0o770)
    File.write!(source, "private media bytes")

    on_exit(fn ->
      File.chmod(parent, 0o700)
      File.rm_rf(parent)
      File.rm(source)
    end)

    digest =
      :crypto.hash(:sha256, "private media bytes")
      |> Base.encode16(case: :lower)

    assert {:error, :unsafe_filesystem_root_parent} =
             FilesystemAdapter.upload(
               source,
               "tenant/intake/episode.mkv",
               %{root: root, owner: nil, file_mode: 0o640, directory_mode: 0o750},
               expected_sha256: digest
             )

    refute File.exists?(root)
  end

  test "publishing rejects a preexisting storage root under a sticky shared parent" do
    parent = Path.join("/tmp", "koe-frame-sticky-parent-#{System.unique_integer([:positive])}")
    root = Path.join(parent, "media")
    source = parent <> "-source.mkv"
    File.mkdir_p!(root)
    File.chmod!(root, 0o750)
    File.write!(source, "private media bytes")

    on_exit(fn ->
      File.chmod(root, 0o700)
      File.rm_rf(parent)
      File.rm(source)
    end)

    digest =
      :crypto.hash(:sha256, "private media bytes")
      |> Base.encode16(case: :lower)

    assert {:error, :unsafe_filesystem_root_parent} =
             FilesystemAdapter.upload(
               source,
               "tenant/intake/episode.mkv",
               %{root: root, owner: nil, file_mode: 0o640, directory_mode: 0o750},
               expected_sha256: digest
             )
  end
end

defmodule Defdo.KoeFrame.MediaIntake.FilesystemAdapterTest do
  use ExUnit.Case, async: true

  alias Defdo.KoeFrame.MediaIntake.FilesystemAdapter

  test "publishing rejects a symlinked parent instead of escaping the media root" do
    root =
      Path.join(
        File.cwd!(),
        ".koe-frame-media-root-#{System.unique_integer([:positive])}"
      )

    external = root <> "-external"
    source = root <> "-source.mkv"
    File.mkdir_p!(root)
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

  test "publishing rejects a storage root beneath a group-writable parent" do
    parent =
      Path.join(
        File.cwd!(),
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
    File.chmod!(root, 0o770)
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

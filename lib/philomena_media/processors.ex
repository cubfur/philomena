defmodule PhilomenaMedia.Processors do
  @moduledoc """
  Utilities for processing uploads.

  Processors have 4 functions available:

  - `versions/1`:
    Takes a version list and generates a list of files which the processor will generate
    during the scope of `process/3`.

  - `process/3`:
    Takes an analysis result, file path, and version list and generates an "edit script" that
    represents how to store this file according to the given version list. See
    `m:Philomena.Images.Thumbnailer` for a usage example.

  - `post_process/2`:
    Takes an analysis result and file path and performs optimizations on the upload. See
    `m:Philomena.Images.Thumbnailer` for a usage example.

  - `intensities/2`:
    Takes an analysis result and file path and generates corner intensities, performing.
    any conversion necessary before processing. See `m:PhilomenaMedia.Intensities`
    for more information.

  ## Version lists

  `process/3` and `post_process/2` take _version lists_ as input. A version list is a structure
  like the following, which contains pairs of _version names_ and _dimensions_:

      [
        thumb_tiny: {50, 50},
        thumb_small: {150, 150},
        thumb: {250, 250},
        small: {320, 240},
        medium: {800, 600},
        large: {1280, 1024},
        tall: {1024, 4096}
      ]

  When calling these functions, it is recommended prefilter the version list based on the media
  dimensions to avoid generating unnecessary versions which are larger than the original file.
  See `m:Philomena.Images.Thumbnailer` for an example.

  ## Edit scripts

  `process/3` and `post_process/2` return _edit scripts_. An edit script is a list where each
  entry may be one of the following:

      {:thumbnails, [copy_requests]}
      {:replace_original, path}
      {:intensities, intensities}

  Within the thumbnail request, a copy request is defined with the following structure:

      {:copy, path, version_filename}

  See the respective functions for more information about their return values.
  """

  alias PhilomenaMedia.Analyzers.Result
  alias PhilomenaMedia.Intensities
  alias PhilomenaMedia.Processors.{Gif, Jpeg, Png, Svg, Webm, Webp}
  alias PhilomenaMedia.Mime

  @typedoc "The name of a version, like `:large`."
  @type version_name :: atom()

  @type dimensions :: {integer(), integer()}
  @type version_list :: [{version_name(), dimensions()}]

  @typedoc "The file name of a processed version, like `large.png`."
  @type version_filename :: String.t()

  @typedoc "A single file to be copied to satisfy a request for a version name."
  @type copy_request :: {:copy, Path.t(), version_filename()}

  @typedoc "A list of thumbnail versions to copy into place."
  @type thumbnails :: {:thumbnails, [copy_request()]}

  @typedoc "Replace the original file to strip metadata or losslessly optimize."
  @type replace_original :: {:replace_original, Path.t()}

  @typedoc "Apply the computed corner intensities."
  @type intensities :: {:intensities, Intensities.t()}

  @typedoc """
  An edit script, representing the changes to apply to the storage backend
  after successful processing.
  """
  @type edit_script :: [thumbnails() | replace_original() | intensities()]

  @doc """
  Returns a processor, with the processor being a module capable
  of processing this content type, or nil.

  The allowed MIME types are:
  - `image/gif`
  - `image/jpeg`
  - `image/png`
  - `image/svg+xml`
  - `video/webm`

  > #### Info {: .info}
  >
  > This is an interface intended for use when the MIME type is already known.
  > Using a processor not matched to the file may cause unexpected results.

  ## Examples

      iex> PhilomenaMedia.Processors.processor("image/png")
      PhilomenaMedia.Processors.Png

      iex> PhilomenaMedia.Processors.processor("application/octet-stream")
      nil

  """
  @spec processor(Mime.t()) :: module() | nil
  def processor(content_type)

  def processor("image/gif"), do: Gif
  def processor("image/jpeg"), do: Jpeg
  def processor("image/png"), do: Png
  def processor("image/svg+xml"), do: Svg
  def processor("video/webm"), do: Webm
  def processor("image/webp"), do: Webp
  def processor(_content_type), do: nil

  @doc """
  Takes a MIME type and filtered version list and generates a list of version files to be
  generated by `process/2`. List contents may differ based on file type.

  ## Examples

      iex> PhilomenaMedia.Processors.versions("image/png", [thumb_tiny: {50, 50}])
      ["thumb_tiny.png"]

      iex> PhilomenaMedia.Processors.versions("video/webm", [thumb_tiny: {50, 50}])
      ["full.mp4", "rendered.png", "thumb_tiny.webm", "thumb_tiny.mp4", "thumb_tiny.gif"]

  """
  @spec versions(Mime.t(), version_list()) :: [version_name()]
  def versions(mime_type, valid_sizes) do
    processor(mime_type).versions(valid_sizes)
  end

  @doc """
  Takes an analyzer result, file path, and version list and runs the appropriate processor's
  `process/3`, processing the media.

  Returns an edit script to apply changes. Depending on the media type, this make take a long
  time to execute.

  ## Example

      iex> PhilomenaMedia.Processors.process(%Result{...}, "image.png", [thumb_tiny: {50, 50}])
      [
        intensities: %Intensities{...},
        thumbnails: [
          {:copy, "/tmp/briefly-5764/vSHsM3kn7k4yvrvZH.png", "thumb_tiny.png"}
        ]
      ]

  """
  @spec process(Result.t(), Path.t(), version_list()) :: edit_script()
  def process(analysis, file, versions) do
    processor(analysis.mime_type).process(analysis, file, versions)
  end

  @doc """
  Takes an analyzer result and file path and runs the appropriate processor's `post_process/2`,
  performing long-running optimizations on the media source file.

  Returns an edit script to apply changes. Depending on the media type, this make take a long
  time to execute. This may also be an empty list, if there are no changes to perform.

  ## Example

      iex> PhilomenaMedia.Processors.post_process(%Result{...}, "image.gif", [thumb_tiny: {50, 50}])
      [replace_original: "/tmp/briefly-5764/cyZSQnmL59XDRoPoaDxr.gif"]

  """
  @spec post_process(Result.t(), Path.t()) :: edit_script()
  def post_process(analysis, file) do
    processor(analysis.mime_type).post_process(analysis, file)
  end

  @doc """
  Takes an analyzer result and file path and runs the appropriate processor's `intensities/2`,
  returning the corner intensities.

  This allows for generating intensities for file types that are not directly supported by
  `m:PhilomenaMedia.Intensities`, and should be the preferred function to call when intensities
  are needed.

  ## Example

    iex> PhilomenaMedia.Processors.intensities(%Result{...}, "video.webm")
    %Intensities{nw: 111.689148, ne: 116.228048, sw: 93.268433, se: 104.630064}

  """
  @spec intensities(Result.t(), Path.t()) :: Intensities.t()
  def intensities(analysis, file) do
    processor(analysis.mime_type).intensities(analysis, file)
  end
end

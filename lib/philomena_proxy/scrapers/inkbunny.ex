defmodule PhilomenaProxy.Scrapers.Inkbunny do
  alias PhilomenaProxy.Http
  alias PhilomenaProxy.Scrapers.Inkbunny.Session

  @url_regex ~r|\Ahttps?://inkbunny\.net/s/([0-9]+)|
  @preview_types ~w(image/jpeg image/png image/gif image/webp)

  @spec can_handle?(URI.t(), String.t()) :: true | false
  def can_handle?(_uri, url) do
    String.match?(url, @url_regex)
  end

  def scrape(_uri, url) do
    [_, submission_id] = Regex.run(@url_regex, url, capture: :all)

    case Session.submission(submission_id) do
      {:ok, submission} ->
        if valid_submission?(submission) do
          scrape_submission(submission, url)
        else
          %{errors: ["Inkbunny returned incomplete submission details. Please try again later."]}
        end

      {:error, message} ->
        %{errors: [message]}
    end
  end

  defp valid_submission?(%{"ratings" => ratings, "files" => files} = submission)
       when is_list(ratings) and is_list(files) do
    Enum.all?(~w(rating_name title description username), &is_binary(submission[&1])) and
      Enum.all?(ratings, &match?(%{"name" => name} when is_binary(name), &1)) and
      Enum.all?(files, fn
        %{"file_url_full" => full, "file_url_screen" => screen}
        when is_binary(full) and is_binary(screen) ->
          true

        _ ->
          false
      end)
  end

  defp valid_submission?(_), do: false

  defp scrape_submission(submission, url) do
    rating = if submission["rating_name"] == "General", do: "safe"
    r = submission["ratings"]

    rating =
      cond do
        r == [] ->
          rating

        Enum.find(r, fn x -> x["name"] == "Strong Violence" end) ->
          "grimdark"

        Enum.find(r, fn x -> x["name"] == "Sexual Themes" end) ->
          "explicit"

        Enum.find(r, fn x -> x["name"] == "Violence" end) ->
          "grimdark"

        Enum.find(r, fn x -> x["name"] == "Nudity" end) ->
          "nude only"

        true ->
          nil
      end

    if rating do
      description = "##\s#{submission["title"]}\n#{submission["description"]}"

      case preview_images(submission["files"]) do
        {:ok, images} ->
          %{
            source_url: url,
            author_name: submission["username"],
            description: description,
            tags: [rating],
            images: images
          }

        :error ->
          %{errors: ["The Inkbunny preview could not be downloaded. Please try again."]}
      end
    else
      %{errors: ["Requested image does not have an acceptable rating for submission."]}
    end
  end

  defp preview_images(files) do
    # Camo cannot set Inkbunny's required Referer. Embed server-fetched previews,
    # as the Pixiv scraper does, while retaining the original URL for upload.
    files
    |> Enum.reduce_while({:ok, []}, fn file, {:ok, images} ->
      with {:ok, %{status: 200, body: body, headers: headers}} <-
             Http.get(file["file_url_screen"]),
           true <- is_binary(body) and byte_size(body) > 0,
           [content_type | _] <- headers["content-type"],
           type = content_type |> String.split(";", parts: 2) |> hd() |> String.trim(),
           true <- type in @preview_types do
        image = %{
          url: file["file_url_full"],
          camo_url: "data:#{type};base64,#{Base.encode64(body)}"
        }

        {:cont, {:ok, [image | images]}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, images} -> {:ok, Enum.reverse(images)}
      :error -> :error
    end
  end
end

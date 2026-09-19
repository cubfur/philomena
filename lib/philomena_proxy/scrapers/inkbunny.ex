defmodule PhilomenaProxy.Scrapers.Inkbunny do
  alias PhilomenaProxy.Scrapers.Inkbunny.Session

  @url_regex ~r|\Ahttps?://inkbunny\.net/s/([0-9]+)|

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

      images =
        for x <- submission["files"] do
          %{
            url: "#{x["file_url_full"]}",
            camo_url: PhilomenaProxy.Camo.image_url(x["file_url_screen"])
          }
        end

      %{
        source_url: url,
        author_name: submission["username"],
        description: description,
        tags: [rating],
        images: images
      }
    else
      %{errors: ["Requested image does not have an acceptable rating for submission."]}
    end
  end
end

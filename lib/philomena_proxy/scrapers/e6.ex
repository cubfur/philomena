defmodule PhilomenaProxy.Scrapers.E6 do
  @behaviour PhilomenaProxy.Scrapers.Scraper

  @url_regex ~r/\A(https\:\/\/(e621|e6ai)\.net\/posts\/([0-9]+))(?:.+)?/

  @spec can_handle?(URI.t(), String.t()) :: true | false
  def can_handle?(_uri, url) do
    String.match?(url, @url_regex)
  end

  def scrape(_uri, url) do
    [_, url, variant, submission_id] = Regex.run(@url_regex, url, capture: :all)

    api_url =
      "https://#{variant}.net/posts/#{submission_id}.json?login=#{e6_user(variant)}&api_key=#{e6_apikey(variant)}"

    case PhilomenaProxy.Http.get(api_url) do
      {:ok, %{status: 200, body: body}} ->
        json = Jason.decode!(body)
        submission = json["post"]

        tags = submission["tags"]["general"] ++ submission["tags"]["species"]

        tags =
          for x <- tags do
            String.replace(x, "_", " ")
          end

        rating =
          case submission["rating"] do
            "s" -> "safe"
            "q" -> "suggestive"
            "e" -> "explicit"
            _ -> nil
          end

        tags = if is_nil(rating), do: tags, else: [rating | tags]

        %{
          source_url: url,
          authors: submission["tags"]["artist"] || [],
          directors: submission["tags"]["director"] || [],
          tags: tags,
          sources: submission["sources"],
          description: submission["description"],
          images: [
            %{
              url: "#{submission["file"]["url"]}",
              camo_url: PhilomenaProxy.Camo.image_url(submission["file"]["url"])
            }
          ]
        }

      _ ->
        %{errors: ["Failed to retrieve image from API"]}
    end
  end

  defp e6_user("e621") do
    Application.get_env(:philomena, :e621_user)
  end

  defp e6_user("e6ai") do
    Application.get_env(:philomena, :e6ai_user)
  end

  defp e6_apikey("e621") do
    Application.get_env(:philomena, :e621_apikey)
  end

  defp e6_apikey("e6ai") do
    Application.get_env(:philomena, :e6ai_apikey)
  end
end

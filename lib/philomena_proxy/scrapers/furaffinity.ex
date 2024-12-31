defmodule PhilomenaProxy.Scrapers.Furaffinity do
  @url_regex ~r|\Ahttps?://www.furaffinity\.net/view/([0-9]+)|

  @spec can_handle?(URI.t(), String.t()) :: true | false
  def can_handle?(_uri, url) do
    String.match?(url, @url_regex)
  end

  def scrape(_uri, url) do
    [_, submission_id] = Regex.run(@url_regex, url, capture: :all)
    api_url = "https://faexport.spangle.org.uk/submission/#{submission_id}.json"
    {:ok, %{status: 200, body: body}} = PhilomenaProxy.Http.get(api_url)

    submission = Jason.decode!(body)

    rating =
      case submission["rating"] do
        "General" -> "safe"
        "Mature" -> "suggestive"
        "Adult" -> "explicit"
        _ -> nil
      end

    description =
      submission["description"]
      |> HtmlSanitizeEx.strip_tags()
      |> String.replace(~r/  +/, " ")
      |> String.replace(~r/\n \n +/, "\n")
      |> String.replace(~r/\n /, "\n")
      |> String.trim()

    description = "##\s#{submission["title"]}\n#{description}"

    %{
      source_url: url,
      author_name: submission["name"],
      description: description,
      tags: [rating],
      images: [
        %{
          url: "#{submission["download"]}",
          camo_url: PhilomenaProxy.Camo.image_url(submission["thumbnail"])
        }
      ]
    }
  end
end

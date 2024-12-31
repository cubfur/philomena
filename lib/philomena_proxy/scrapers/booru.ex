defmodule PhilomenaProxy.Scrapers.Booru do
  @behaviour PhilomenaProxy.Scrapers.Scraper

  @url_regex ~r/\A(https\:\/\/(derpi|fur)booru\.org\/images\/([0-9]+))(?:.+)?/

  @spec can_handle?(URI.t(), String.t()) :: true | false
  def can_handle?(_uri, url) do
    String.match?(url, @url_regex)
  end

  def scrape(_uri, url) do
    [_, url, variant, submission_id] = Regex.run(@url_regex, url, capture: :all)

    api_url =
      "https://#{variant}booru.org/api/v1/json/images/#{submission_id}"

    {:ok, %{status: 200, body: body}} = PhilomenaProxy.Http.get(api_url)

    json = Jason.decode!(body)
    submission = json["image"]

    tags = submission["tags"]

    %{
      source_url: url,
      tags: tags,
      sources: submission["source_urls"],
      description: submission["description"],
      images: [
        %{
          url: "#{submission["representations"]["full"]}",
          camo_url: PhilomenaProxy.Camo.image_url(submission["representations"]["medium"])
        }
      ]
    }
  end
end

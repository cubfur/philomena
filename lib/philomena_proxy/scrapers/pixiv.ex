defmodule PhilomenaProxy.Scrapers.Pixiv do
  @url_regex ~r|\Ahttps?://www\.pixiv\.net/en/artworks/([0-9]+)|

  @spec can_handle?(URI.t(), String.t()) :: true | false
  def can_handle?(_uri, url) do
    String.match?(url, @url_regex)
  end

  def scrape(_uri, url) do
    [_, submission_id] = Regex.run(@url_regex, url, capture: :all)
    api_url = "https://www.pixiv.net/touch/ajax/illust/details?illust_id=#{submission_id}"

    {:ok, %{status: 200, body: body}} =
      PhilomenaProxy.Http.get(api_url, [{"Referer", "https://pixiv.net/"}])

    json = Jason.decode!(body)
    submission = json["body"]

    description =
      "##\s#{submission["illust_details"]["title"]}\n#{submission["illust_details"]["comment"]}"

    images =
      if submission["illust_details"]["manga_a"] do
        submission["illust_details"]["manga_a"]
      else
        [submission["illust_details"]]
      end

    images =
      for x <- images do
        pre = x["url_small"] || x["url_s"]

        {:ok, %{status: 200, body: body, headers: headers}} =
          PhilomenaProxy.Http.get(pre, [{"Referer", "https://pixiv.net/"}])

        type =
          headers
          |> Enum.into(%{})
          |> Map.get("content-type")

        %{
          url: x["url_big"],
          camo_url: "data:#{type};base64,#{Base.encode64(body)}"
        }
      end

    %{
      source_url: url,
      author_name: submission["author_details"]["user_account"],
      description: description,
      images: images
    }
  end
end

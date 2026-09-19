defmodule PhilomenaProxy.Scrapers.InkbunnyTest do
  use ExUnit.Case, async: false

  alias PhilomenaProxy.Scrapers.Inkbunny

  setup do
    keys = [:inkbunny_sid, :inkbunny_username, :inkbunny_password, :req_options]
    previous = Map.new(keys, &{&1, Application.fetch_env(:philomena, &1)})
    Application.put_env(:philomena, :inkbunny_sid, "test-session")
    Application.delete_env(:philomena, :inkbunny_username)
    Application.delete_env(:philomena, :inkbunny_password)
    Application.put_env(:philomena, :req_options, plug: {Req.Test, PhilomenaProxy.Http})

    on_exit(fn ->
      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:philomena, key, value)
          :error -> Application.delete_env(:philomena, key)
        end
      end
    end)

    :ok
  end

  test "expired SID without credentials returns a scraper error instead of raising" do
    Req.Test.stub(PhilomenaProxy.Http, fn conn ->
      Req.Test.json(conn, %{error_code: 2, error_message: "Expired test-session"})
    end)

    assert %{errors: [message]} = scrape()
    assert is_binary(message)
    refute message =~ "test-session"
  end

  test "successful authenticated response retains source and submission metadata" do
    Req.Test.stub(PhilomenaProxy.Http, fn conn ->
      assert conn.method == "POST"
      assert conn.query_string == ""

      Req.Test.json(conn, %{
        submissions: [
          %{
            submission_id: "123",
            rating_name: "General",
            ratings: [],
            title: "Example",
            description: "A description",
            username: "example_artist",
            files: []
          }
        ]
      })
    end)

    assert %{
             source_url: "https://inkbunny.net/s/123",
             author_name: "example_artist",
             tags: ["safe"],
             images: [],
             description: "## Example\nA description"
           } = scrape()
  end

  test "incomplete submission details return a scraper error instead of raising" do
    Req.Test.stub(PhilomenaProxy.Http, fn conn ->
      Req.Test.json(conn, %{submissions: [%{submission_id: "123"}]})
    end)

    assert %{errors: ["Inkbunny returned incomplete submission details." <> _]} = scrape()
  end

  defp scrape do
    url = "https://inkbunny.net/s/123"
    Inkbunny.scrape(URI.parse(url), url)
  end
end

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

  test "fetches both previews with the required Referer and keeps original upload URLs" do
    owner = self()

    files =
      for id <- [1, 2],
          do: %{
            file_url_full: "https://tx.ib.metapix.net/files/full/#{id}.jpg",
            file_url_screen: "https://tx.ib.metapix.net/files/screen/#{id}.jpg"
          }

    Req.Test.stub(PhilomenaProxy.Http, fn conn ->
      case conn.request_path do
        "/api_submissions.php" ->
          Req.Test.json(conn, %{submissions: [submission(files)]})

        path ->
          assert conn.method == "GET"
          assert Plug.Conn.get_req_header(conn, "referer") == ["https://inkbunny.net"]
          send(owner, {:preview, path})

          conn
          |> Plug.Conn.put_resp_content_type("image/jpeg")
          |> Plug.Conn.resp(200, "preview-#{path}")
      end
    end)

    assert %{images: [first, second]} = scrape()
    assert first.url == "https://tx.ib.metapix.net/files/full/1.jpg"
    assert second.url == "https://tx.ib.metapix.net/files/full/2.jpg"

    assert first.camo_url ==
             "data:image/jpeg;base64," <> Base.encode64("preview-/files/screen/1.jpg")

    assert second.camo_url ==
             "data:image/jpeg;base64," <> Base.encode64("preview-/files/screen/2.jpg")

    assert_received {:preview, "/files/screen/1.jpg"}
    assert_received {:preview, "/files/screen/2.jpg"}
    refute_received {:preview, "/files/full/1.jpg"}
  end

  for {status, type, body} <- [
        {403, "text/html", "Forbidden"},
        {200, "text/html", "Not an image"},
        {200, "image/jpeg", ""}
      ] do
    test "reports preview failure for #{status} #{type} #{inspect(body)}" do
      Req.Test.stub(PhilomenaProxy.Http, fn conn ->
        if conn.request_path == "/api_submissions.php" do
          Req.Test.json(conn, %{
            submissions: [
              submission([
                %{
                  file_url_full: "https://tx.ib.metapix.net/files/full/1.jpg",
                  file_url_screen: "https://tx.ib.metapix.net/files/screen/1.jpg"
                }
              ])
            ]
          })
        else
          conn
          |> Plug.Conn.put_resp_content_type(unquote(type))
          |> Plug.Conn.resp(unquote(status), unquote(body))
        end
      end)

      assert %{errors: ["The Inkbunny preview could not be downloaded. Please try again."]} =
               scrape()
    end
  end

  test "the upload plug downloads the selected original with the required Referer" do
    Req.Test.stub(PhilomenaProxy.Http, fn conn ->
      if Plug.Conn.get_req_header(conn, "referer") == ["https://inkbunny.net"] do
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.resp(200, "original-image-bytes")
      else
        Plug.Conn.resp(conn, 403, "Forbidden")
      end
    end)

    conn = Plug.Test.conn(:post, "/images")

    conn = %{
      conn
      | params: %{"image" => %{}, "scraper_cache" => "https://tx.ib.metapix.net/files/full/1.jpg"}
    }

    result = PhilomenaWeb.ScraperPlug.call(conn, [])
    assert %Plug.Upload{path: path, filename: "1.jpg"} = result.params["image"]["image"]
    on_exit(fn -> File.rm(path) end)
    assert File.read!(path) == "original-image-bytes"
  end

  defp submission(files) do
    %{
      submission_id: "123",
      rating_name: "General",
      ratings: [],
      title: "Example",
      description: "A description",
      username: "example_artist",
      files: files
    }
  end

  defp scrape do
    url = "https://inkbunny.net/s/123"
    Inkbunny.scrape(URI.parse(url), url)
  end
end

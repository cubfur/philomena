defmodule PhilomenaProxy.HttpTest do
  use ExUnit.Case, async: false

  alias PhilomenaProxy.Http

  setup {Req.Test, :verify_on_exit!}

  setup do
    previous = Application.fetch_env(:philomena, :req_options)
    Application.put_env(:philomena, :req_options, plug: {Req.Test, Http})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:philomena, :req_options, value)
        :error -> Application.delete_env(:philomena, :req_options)
      end
    end)

    :ok
  end

  for method <- [:get, :head],
      host <- ["inkbunny.net", "ib.metapix.net", "tx.ib.metapix.net", "TX.IB.METAPIX.NET"] do
    test "#{method} sends the required Referer to #{host}" do
      Req.Test.expect(Http, fn conn ->
        assert conn.method == unquote(method |> Atom.to_string() |> String.upcase())
        assert Plug.Conn.get_req_header(conn, "referer") == ["https://inkbunny.net"]
        Req.Test.text(conn, "image bytes")
      end)

      assert {:ok, %{status: 200}} =
               apply(Http, unquote(method), ["https://#{unquote(host)}/files/full/image.jpg"])
    end
  end

  for url <- [
        "https://example.com/image.jpg",
        "https://notinkbunny.net/image.jpg",
        "https://inkbunny.net.example.com/image.jpg",
        "https://notib.metapix.net/image.jpg",
        "https://tx.ib.metapix.net.example.com/image.jpg",
        "https://metapix.net/image.jpg",
        "https://example.com/tx.ib.metapix.net/image.jpg",
        "http://inkbunny.net/image.jpg",
        "http://tx.ib.metapix.net/image.jpg"
      ] do
    test "does not add an Inkbunny Referer for #{url}" do
      Req.Test.expect(Http, fn conn ->
        assert Plug.Conn.get_req_header(conn, "referer") == []
        Req.Test.text(conn, "image bytes")
      end)

      assert {:ok, %{status: 200}} = Http.get(unquote(url))
    end
  end

  for header <- ["referer", "Referer", "REFERER", :referer], method <- [:get, :head] do
    test "#{method} preserves an explicit #{inspect(header)} header" do
      Req.Test.expect(Http, fn conn ->
        assert Plug.Conn.get_req_header(conn, "referer") == ["https://example.com/source"]
        Req.Test.text(conn, "image bytes")
      end)

      assert {:ok, %{status: 200}} =
               apply(Http, unquote(method), [
                 "https://tx.ib.metapix.net/image.jpg",
                 [{unquote(header), "https://example.com/source"}]
               ])
    end
  end

  test "does not add a Referer to Inkbunny API POST requests" do
    Req.Test.expect(Http, fn conn ->
      assert conn.method == "POST"
      assert Plug.Conn.get_req_header(conn, "referer") == []
      Req.Test.json(conn, %{})
    end)

    assert {:ok, %{status: 200}} = Http.post("https://inkbunny.net/api_submissions.php", "")
  end
end

defmodule PhilomenaProxy.Scrapers.Inkbunny.SessionTest do
  use ExUnit.Case, async: false

  alias PhilomenaProxy.Http
  alias PhilomenaProxy.Scrapers.Inkbunny.Session

  @config_keys [:inkbunny_sid, :inkbunny_username, :inkbunny_password]

  setup {Req.Test, :verify_on_exit!}

  setup do
    saved = Map.new(@config_keys, &{&1, Application.fetch_env(:philomena, &1)})
    Enum.each(@config_keys, &Application.delete_env(:philomena, &1))

    on_exit(fn ->
      Enum.each(saved, fn
        {key, {:ok, value}} -> Application.put_env(:philomena, key, value)
        {key, :error} -> Application.delete_env(:philomena, key)
      end)
    end)

    :ok
  end

  test "reuses an existing SID without needing credentials or logging in" do
    Application.put_env(:philomena, :inkbunny_sid, " existing-session ")

    Req.Test.expect(Http, 2, fn conn ->
      assert conn.request_path == "/api_submissions.php"

      assert form(conn) == %{
               "sid" => "existing-session",
               "submission_ids" => "123",
               "show_description" => "yes"
             }

      Req.Test.json(conn, %{submissions: [%{submission_id: "123"}]})
    end)

    assert Session.submission("123") == {:ok, %{"submission_id" => "123"}}
    assert Session.submission("123") == {:ok, %{"submission_id" => "123"}}
  end

  test "logs in when the SID is blank, preserves password bytes, and caches the session" do
    Application.put_env(:philomena, :inkbunny_sid, " \n ")
    credentials(" account ", " p&ss+word=雪 \n")

    Req.Test.expect(Http, fn conn ->
      assert conn.request_path == "/api_login.php"
      assert form(conn) == %{"username" => "account", "password" => " p&ss+word=雪 \n"}
      Req.Test.json(conn, %{sid: "renewed-session"})
    end)

    Req.Test.expect(Http, 2, fn conn ->
      assert conn.request_path == "/api_submissions.php"
      assert form(conn)["sid"] == "renewed-session"
      Req.Test.json(conn, %{submissions: [%{submission_id: "123"}]})
    end)

    assert {:ok, _} = Session.submission("123")
    assert Application.get_env(:philomena, :inkbunny_sid) == "renewed-session"
    assert {:ok, _} = Session.submission("123")
  end

  for error_code <- [2, "2"] do
    test "renews an expired SID after error #{inspect(error_code)} and retries the submission" do
      Application.put_env(:philomena, :inkbunny_sid, "old-session")
      credentials()

      Req.Test.expect(Http, fn conn ->
        assert conn.request_path == "/api_submissions.php"
        assert form(conn)["sid"] == "old-session"

        Req.Test.json(conn, %{
          error_code: unquote(error_code),
          error_message: "secret old-session"
        })
      end)

      Req.Test.expect(Http, fn conn ->
        assert conn.request_path == "/api_login.php"
        Req.Test.json(conn, %{sid: "new-session"})
      end)

      Req.Test.expect(Http, fn conn ->
        assert conn.request_path == "/api_submissions.php"
        assert form(conn)["sid"] == "new-session"
        Req.Test.json(conn, %{submissions: [%{submission_id: "123"}]})
      end)

      assert Session.submission("123") == {:ok, %{"submission_id" => "123"}}
    end
  end

  test "concurrent expired requests share one refreshed session" do
    Application.put_env(:philomena, :inkbunny_sid, "old-session")
    credentials()
    owner = self()

    Req.Test.stub(Http, fn conn ->
      case {conn.request_path, form(conn)} do
        {"/api_submissions.php", %{"sid" => "old-session"}} ->
          send(owner, {:old_session_request, self()})

          receive do
            :release -> Req.Test.json(conn, %{error_code: 2})
          after
            5_000 -> flunk("concurrent requests did not reach the expiry barrier")
          end

        {"/api_login.php", _} ->
          send(owner, :login_request)
          Req.Test.json(conn, %{sid: "new-session"})

        {"/api_submissions.php", %{"sid" => "new-session"}} ->
          Req.Test.json(conn, %{submissions: [%{submission_id: "123"}]})
      end
    end)

    tasks = for _ <- 1..4, do: Task.async(fn -> Session.submission("123") end)

    waiting =
      for _ <- tasks do
        assert_receive {:old_session_request, pid}, 5_000
        pid
      end

    Enum.each(waiting, &send(&1, :release))

    Enum.each(tasks, fn task ->
      assert Task.await(task, 5_000) == {:ok, %{"submission_id" => "123"}}
    end)

    assert_received :login_request
    refute_received :login_request
  end

  test "stops after a single renewal when the new SID is also rejected" do
    Application.put_env(:philomena, :inkbunny_sid, "old-session")
    credentials()

    Req.Test.expect(Http, fn conn -> Req.Test.json(conn, %{error_code: 2}) end)
    Req.Test.expect(Http, fn conn -> Req.Test.json(conn, %{sid: "new-session"}) end)
    Req.Test.expect(Http, fn conn -> Req.Test.json(conn, %{error_code: "2"}) end)

    assert {:error, message} = Session.submission("123")
    assert message =~ "rejected the renewed session"
  end

  test "missing credentials return a clear error without sending a login" do
    credentials(" \n ", "password")
    assert {:error, message} = Session.submission("123")
    assert message =~ "configured login credentials"

    credentials("account", "")
    assert {:error, ^message} = Session.submission("123")
  end

  test "an expired SID without credentials returns an error instead of crashing" do
    Application.put_env(:philomena, :inkbunny_sid, "old-session")
    Req.Test.expect(Http, fn conn -> Req.Test.json(conn, %{error_code: 2}) end)

    assert {:error, message} = Session.submission("123")
    assert message =~ "configured login credentials"
  end

  test "invalid credentials do not leak an upstream error or replace the cached SID" do
    Application.put_env(:philomena, :inkbunny_sid, "old-session")
    credentials()

    Req.Test.expect(Http, fn conn -> Req.Test.json(conn, %{error_code: 2}) end)

    Req.Test.expect(Http, fn conn ->
      Req.Test.json(conn, %{error_code: "0", error_message: "secret password", sid: "secret sid"})
    end)

    assert {:error, message} = Session.submission("123")
    assert message =~ "login failed"
    refute message =~ "secret"
    assert Application.get_env(:philomena, :inkbunny_sid) == "old-session"
  end

  for body <- ["invalid JSON secret", "[]", "null", "{}", ~s({"sid":"  "})] do
    test "rejects malformed login response #{inspect(body)} without exposing its contents" do
      credentials()
      Req.Test.expect(Http, fn conn -> Req.Test.text(conn, unquote(body)) end)

      assert {:error, message} = Session.submission("123")
      assert message =~ "unexpected response"
      refute message =~ "secret"
      assert Application.get_env(:philomena, :inkbunny_sid) == nil
    end
  end

  test "network failures and server errors return safe errors without retries" do
    credentials()
    Req.Test.expect(Http, fn conn -> Req.Test.transport_error(conn, :timeout) end)
    assert {:error, message} = Session.submission("123")
    assert message =~ "Unable to contact Inkbunny"

    Req.Test.expect(Http, fn conn -> Plug.Conn.send_resp(conn, 503, "secret response") end)
    assert {:error, ^message} = Session.submission("123")
  end

  test "redirects are not followed with login credentials" do
    credentials()

    Req.Test.expect(Http, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "https://example.com/collect")
      |> Plug.Conn.send_resp(307, "")
    end)

    assert {:error, message} = Session.submission("123")
    assert message =~ "Unable to contact Inkbunny"
  end

  test "non-session API errors and missing submissions do not trigger login" do
    Application.put_env(:philomena, :inkbunny_sid, "valid-session")
    credentials()

    Req.Test.expect(Http, fn conn ->
      assert conn.request_path == "/api_submissions.php"
      Req.Test.json(conn, %{error_code: 40, error_message: "private details"})
    end)

    assert {:error, message} = Session.submission("123")
    assert message =~ "submission is unavailable"
    refute message =~ "private details"

    Req.Test.expect(Http, fn conn -> Req.Test.json(conn, %{submissions: []}) end)
    assert {:error, ^message} = Session.submission("123")
  end

  test "malformed submission responses return errors instead of crashing" do
    Application.put_env(:philomena, :inkbunny_sid, "valid-session")

    for response <- [%{}, %{submissions: nil}, %{submissions: [nil]}, %{submissions: [%{}, %{}]}] do
      Req.Test.expect(Http, fn conn -> Req.Test.json(conn, response) end)
      assert {:error, message} = Session.submission("123")
      assert message =~ "unexpected response"
    end
  end

  defp credentials(username \\ "account", password \\ "password") do
    Application.put_env(:philomena, :inkbunny_username, username)
    Application.put_env(:philomena, :inkbunny_password, password)
  end

  defp form(conn) do
    assert conn.method == "POST"
    assert conn.scheme == :https
    assert conn.host == "inkbunny.net"
    assert conn.query_string == ""
    assert Plug.Conn.get_req_header(conn, "content-type") == ["application/x-www-form-urlencoded"]
    {:ok, body, _} = Plug.Conn.read_body(conn)
    URI.decode_query(body)
  end
end

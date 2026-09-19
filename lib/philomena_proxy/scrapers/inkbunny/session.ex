defmodule PhilomenaProxy.Scrapers.Inkbunny.Session do
  @moduledoc false

  alias PhilomenaProxy.Http

  @api_url "https://inkbunny.net/"
  @headers [{"content-type", "application/x-www-form-urlencoded"}]
  @request_error "Unable to contact Inkbunny. Please try again later."
  @response_error "Inkbunny returned an unexpected response. Please try again later."
  @credentials_error "Inkbunny needs a valid session or configured login credentials. Please contact an administrator."
  @login_error "Inkbunny login failed. Please ask an administrator to check the credentials and API access setting."
  @expired_error "Inkbunny rejected the renewed session. Please try again later."
  @submission_error "The requested Inkbunny submission is unavailable to the configured account."

  @spec submission(String.t()) :: {:ok, map()} | {:error, String.t()}
  def submission(id) do
    with {:ok, sid} <- current_session() do
      case fetch_submission(id, sid) do
        {:error, :expired} ->
          with {:ok, renewed_sid} <- refresh(sid) do
            case fetch_submission(id, renewed_sid) do
              {:error, :expired} -> {:error, @expired_error}
              result -> result
            end
          end

        result ->
          result
      end
    end
  end

  defp current_session do
    case cached_sid() do
      nil -> refresh(nil)
      sid -> {:ok, sid}
    end
  end

  defp refresh(rejected_sid) do
    # All requests in this VM share a session. A request that failed using an
    # older SID can reuse a session another request has already renewed.
    :global.trans(
      {__MODULE__, self()},
      fn ->
        case cached_sid() do
          sid when not is_nil(sid) and sid != rejected_sid -> {:ok, sid}
          _ -> login()
        end
      end,
      [node()]
    )
  end

  defp login do
    username = nonblank(Application.get_env(:philomena, :inkbunny_username))
    password = Application.get_env(:philomena, :inkbunny_password)

    if username && is_binary(password) && byte_size(password) > 0 do
      with {:ok, response} <- request("api_login.php", username: username, password: password) do
        case response do
          %{"error_code" => _} ->
            {:error, @login_error}

          %{"sid" => value} ->
            case nonblank(value) do
              nil ->
                {:error, @response_error}

              sid ->
                Application.put_env(:philomena, :inkbunny_sid, sid)
                {:ok, sid}
            end

          _ ->
            {:error, @response_error}
        end
      end
    else
      {:error, @credentials_error}
    end
  end

  defp fetch_submission(id, sid) do
    with {:ok, response} <-
           request("api_submissions.php", sid: sid, submission_ids: id, show_description: "yes") do
      case response do
        %{"error_code" => code} when code in [2, "2"] -> {:error, :expired}
        %{"error_code" => _} -> {:error, @submission_error}
        %{"submissions" => [submission]} when is_map(submission) -> {:ok, submission}
        %{"submissions" => []} -> {:error, @submission_error}
        _ -> {:error, @response_error}
      end
    end
  end

  defp request(endpoint, params) do
    case Http.post(@api_url <> endpoint, URI.encode_query(params), @headers,
           redirect: false,
           retry: false
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        case JSON.decode(body) do
          {:ok, response} when is_map(response) -> {:ok, response}
          _ -> {:error, @response_error}
        end

      _ ->
        {:error, @request_error}
    end
  end

  defp cached_sid, do: nonblank(Application.get_env(:philomena, :inkbunny_sid))

  defp nonblank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nonblank(_), do: nil
end

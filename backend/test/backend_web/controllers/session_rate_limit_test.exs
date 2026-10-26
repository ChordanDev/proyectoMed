defmodule BackendWeb.SessionRateLimitTest do
  @moduledoc """
  Throttling of the learner session routes that call paid providers (#395):
  per session and per learner, beyond the limit they answer `429
  rate_limited` with a `retry-after` header. The voice-worker routes are never
  throttled, so no spoken turn is dropped.
  """

  # The limiter's counters and the application env are shared: not async.
  use BackendWeb.ConnCase, async: false

  @moduletag :capture_log

  import ExUnit.CaptureLog
  import Backend.AccountsFixtures
  import Backend.BillingFixtures
  import BackendWeb.RateLimitHelpers

  alias Backend.Content
  alias Backend.Stations

  @reference_case File.read!("priv/stations/acute-appendicitis/case.md")

  @message %{"role" => "learner", "modality" => "text", "text" => "Bom dia, o que sente?"}

  # Every paid learner route: {action, method, path suffix, params}.
  @paid_routes [
    {:session_message, :post, "/messages", @message},
    {:session_transcribe, :post, "/transcribe", %{}},
    {:session_synthesize, :post, "/synthesize", %{"text" => "Bom dia."}},
    {:session_voice, :post, "/voice", %{}},
    {:session_impresso, :post, "/impressos/request", %{"text" => "hemograma"}},
    {:session_exam_mode, :post, "/exam-mode", %{}},
    {:session_exam_mode, :delete, "/exam-mode", %{}},
    {:session_result, :get, "/result", %{}}
  ]

  setup do
    admin = admin_fixture()
    {:ok, package} = Stations.parse_case(@reference_case)

    %{rows: [[id]]} =
      Backend.Repo.query!(
        "INSERT INTO cases (area, theme, markdown) VALUES ($1, $2, $3) RETURNING id",
        ["Cirurgia Geral", "Tema", @reference_case]
      )

    {:ok, kase} = Content.approve_case(Content.get_case!(id), package, admin)
    %{kase: kase}
  end

  defp learner_conn(conn), do: log_in_device(conn, user_fixture() |> subscribe_user())

  defp start_session!(conn, kase) do
    conn
    |> recycle()
    |> post(~p"/sessions", %{"station_id" => kase.number, "audio_consent" => false})
    |> json_response(201)
    |> Map.fetch!("session_id")
  end

  defp request(conn, method, path, params),
    do: conn |> recycle() |> dispatch(@endpoint, method, path, params)

  defp assert_rate_limited(response) do
    assert %{"error" => "rate_limited", "message" => message} = json_response(response, 429)
    assert message =~ "Aguarde"
    assert [retry_after] = get_resp_header(response, "retry-after")
    assert String.to_integer(retry_after) >= 1
  end

  describe "per session" do
    for {action, method, suffix, params} <- @paid_routes do
      @action action
      @method method
      @suffix suffix
      @params params

      test "#{method |> to_string() |> String.upcase()} /sessions/:id#{suffix} answers 429 beyond the #{action} limit",
           %{conn: conn, kase: kase} do
        enable_rate_limit([{@action, session: {2, 60_000}}])
        learner = learner_conn(conn)
        session_id = start_session!(learner, kase)
        path = "/sessions/#{session_id}#{@suffix}"

        for _ <- 1..2 do
          refute request(learner, @method, path, @params).status == 429
        end

        {limited, log} = with_log(fn -> request(learner, @method, path, @params) end)
        assert_rate_limited(limited)
        assert log =~ "rate limited action=#{@action} keys=session"
        refute log =~ session_id

        # Another learner's session is counted apart.
        other = learner_conn(build_conn())
        other_path = "/sessions/#{start_session!(other, kase)}#{@suffix}"
        refute request(other, @method, other_path, @params).status == 429
      end
    end

    test "every action is counted apart", %{conn: conn, kase: kase} do
      enable_rate_limit(session_message: [session: {1, 60_000}])
      learner = learner_conn(conn)
      session_id = start_session!(learner, kase)

      refute request(learner, :post, "/sessions/#{session_id}/messages", @message).status == 429

      assert_rate_limited(request(learner, :post, "/sessions/#{session_id}/messages", @message))

      refute request(learner, :post, "/sessions/#{session_id}/impressos/request", %{
               "text" => "hemograma"
             }).status == 429
    end

    test "the deprecated active-station aliases share the session's counter",
         %{conn: conn, kase: kase} do
      enable_rate_limit(session_message: [session: {1, 60_000}])
      learner = learner_conn(conn)
      session_id = start_session!(learner, kase)

      refute request(learner, :post, "/sessions/#{session_id}/messages", @message).status == 429

      assert_rate_limited(
        request(learner, :post, "/api/stations/active/sessions/#{session_id}/messages", @message)
      )
    end
  end

  describe "per learner" do
    test "counts the learner's requests across sessions", %{conn: conn, kase: kase} do
      enable_rate_limit(session_message: [session: {100, 60_000}, learner: {2, 60_000}])
      learner = learner_conn(conn)
      first = start_session!(learner, kase)

      for _ <- 1..2 do
        refute request(learner, :post, "/sessions/#{first}/messages", @message).status == 429
      end

      assert request(learner, :post, "/sessions/#{first}/discard", %{}).status == 204
      second = start_session!(learner, kase)

      assert_rate_limited(request(learner, :post, "/sessions/#{second}/messages", @message))
    end
  end

  describe "the voice worker" do
    @secret "issue-395-worker-secret"

    setup do
      previous = Application.get_env(:backend, :voice_worker_secret)
      Application.put_env(:backend, :voice_worker_secret, @secret)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:backend, :voice_worker_secret, previous),
          else: Application.delete_env(:backend, :voice_worker_secret)
      end)
    end

    test "is never throttled, so no spoken turn is dropped", %{conn: conn, kase: kase} do
      limits = for {action, _, _, _} <- @paid_routes, do: {action, session: {1, 60_000}}
      enable_rate_limit(limits)
      session_id = start_session!(learner_conn(conn), kase)

      worker = put_req_header(build_conn(), "authorization", "Bearer " <> @secret)

      for _ <- 1..5 do
        refute request(worker, :get, "/api/internal/voice/sessions/#{session_id}", %{}).status ==
                 429

        refute request(worker, :post, "/api/internal/voice/sessions/#{session_id}/transcripts", %{
                 "turn_id" => "",
                 "text" => ""
               }).status == 429
      end
    end
  end
end

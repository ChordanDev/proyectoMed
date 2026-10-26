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

  alias Backend.AppEnvHelpers
  alias Backend.Content
  alias Backend.Stations

  defmodule PatientAdapter do
    @behaviour Backend.Stations.StationAI
    @impl true
    def next_reply(_package, _context), do: {:ok, %{text: "Estou com dor na barriga."}}
  end

  defmodule VerifyingJevAdapter do
    @behaviour Backend.Stations.JevDecision.Adapter
    @impl true
    def decide_patient(_request), do: {:ok, %{status: :verified}}
    @impl true
    def decide_rubric(_request), do: {:error, :not_implemented}
  end

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

    # Every deprecated alias of a paid route: {action, method, alias prefix,
    # path suffix, params}.
    @aliases [
      {:session_message, :post, "/api/stations/active/sessions", "/messages", @message},
      {:session_result, :get, "/api/stations/active/sessions", "/result", %{}},
      {:session_result, :get, "/api/v2/stations/active/sessions", "/result", %{}},
      {:session_impresso, :post, "/api/stations/active/sessions", "/impressos/request",
       %{"text" => "hemograma"}},
      {:session_transcribe, :post, "/api/stations/active/sessions", "/transcribe", %{}},
      {:session_synthesize, :post, "/api/stations/active/sessions", "/synthesize",
       %{"text" => "Bom dia."}},
      {:session_voice, :post, "/api/stations/active/sessions", "/voice", %{}}
    ]

    for {action, method, prefix, suffix, params} <- @aliases do
      @action action
      @method method
      @prefix prefix
      @suffix suffix
      @params params

      test "the deprecated alias #{prefix}/:id#{suffix} shares the session's #{action} counter",
           %{conn: conn, kase: kase} do
        enable_rate_limit([{@action, session: {1, 60_000}}])
        learner = learner_conn(conn)
        session_id = start_session!(learner, kase)

        refute request(learner, @method, "/sessions/#{session_id}#{@suffix}", @params).status ==
                 429

        assert_rate_limited(
          request(learner, @method, "#{@prefix}/#{session_id}#{@suffix}", @params)
        )
      end
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

    test "requests a session refuses spend none of the learner's budget",
         %{conn: conn, kase: kase} do
      enable_rate_limit(session_message: [session: {2, 60_000}, learner: {3, 60_000}])
      learner = learner_conn(conn)
      first = start_session!(learner, kase)

      for _ <- 1..2 do
        refute request(learner, :post, "/sessions/#{first}/messages", @message).status == 429
      end

      for _ <- 1..2 do
        assert_rate_limited(request(learner, :post, "/sessions/#{first}/messages", @message))
      end

      assert request(learner, :post, "/sessions/#{first}/discard", %{}).status == 204
      second = start_session!(learner, kase)

      refute request(learner, :post, "/sessions/#{second}/messages", @message).status == 429
    end
  end

  describe "the voice worker" do
    @secret "issue-395-worker-secret"

    setup do
      put_backend_env(:voice_worker_secret, @secret)
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

  describe "a normal 10-minute station" do
    setup do
      put_backend_env(:station_ai_adapter, PatientAdapter)
      put_backend_env(:jev_decision_adapter, VerifyingJevAdapter)
    end

    test "is never throttled at the default limits", %{conn: conn, kase: kase} do
      enable_rate_limit()
      learner = learner_conn(conn)
      session_id = start_session!(learner, kase)
      path = &"/sessions/#{session_id}#{&1}"

      send! = fn method, suffix, params ->
        response = request(learner, method, path.(suffix), params)
        refute response.status == 429, "#{method} #{suffix} was throttled"
        response
      end

      # The client joins the voice room, and reconnects once.
      for _ <- 1..2, do: send!.(:post, "/voice", %{})

      # A turn every 4 s for 10 minutes, over the turn-based voice path: the
      # learner's audio, the turn, the patient's audio.
      for turn <- 1..150 do
        send!.(:post, "/transcribe", %{})

        response = send!.(:post, "/messages", %{@message | "text" => "Pergunta #{turn}"})
        assert response.status in 200..299

        send!.(:post, "/synthesize", %{"text" => "Estou com dor na barriga."})

        # Halfway through, a handful of impresso requests and spoken exam
        # requests (the exam button arms, and once cancels, the exam mode).
        if turn in 75..80 do
          send!.(:post, "/impressos/request", %{"text" => "hemograma #{turn}"})
          send!.(:post, "/exam-mode", %{})
        end

        if turn == 80, do: send!.(:delete, "/exam-mode", %{})

        advance_rate_limit_clock(4_000)
      end

      assert %{"status" => "completed"} =
               request(learner, :post, path.("/finish"), %{}) |> json_response(200)

      # The client fetches the result once; ten retries every 2 s stay under the limit.
      for _ <- 1..10 do
        send!.(:get, "/result", %{})
        advance_rate_limit_clock(2_000)
      end
    end
  end

  defp put_backend_env(key, value) do
    previous = AppEnvHelpers.snapshot(key)
    Application.put_env(:backend, key, value)
    on_exit(fn -> AppEnvHelpers.restore(key, previous) end)
  end
end

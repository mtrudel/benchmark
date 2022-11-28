defmodule Benchmark.Server do
  @moduledoc false

  require Logger

  def run(server_def, func) do
    {:ok, server_pid} = start_server(server_def)
    Logger.debug("Waiting for #{server_def.server} to start")
    wait_for_server(server_def)
    Logger.debug("Server started; ready to go")
    Process.sleep(1000)

    result = func.()

    Logger.debug("Waiting for #{server_def.server} to stop")
    stop_server(server_pid)
    Process.sleep(1000)
    Logger.debug("Server stopped")

    result
  end

  defp start_server(server_def) do
    MuonTrap.Daemon.start_link("elixir", ["-e", server_script(server_def)],
      stderr_to_stdout: true,
      log_output: :debug
    )
  end

  defp stop_server(pid), do: GenServer.stop(pid)

  defp wait_for_server(server_def, count \\ 60_000)
  defp wait_for_server(_server_def, 0), do: raise("Timeout waiting for server to be ready")

  defp wait_for_server(server_def, count) do
    Finch.build(:get, "http://#{server_def.hostname}:#{server_def.port}")
    |> Finch.request(BenchmarkFinch)
    |> case do
      {:ok, %Finch.Response{}} ->
        :ok

      _ ->
        Process.sleep(200)
        wait_for_server(server_def, count - 200)
    end
  end

  defp server_script(%{server: "bandit", treeish: "local", port: port}) do
    quote do
      unquote(memory_monitor())
      Mix.install([{:bandit, path: "../bandit"}])
      unquote(plug_def())
      Bandit.start_link(plug: BenchmarkPlug, options: [port: unquote(port)])
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp server_script(%{server: "bandit", repo: repo, treeish: treeish, port: port}) do
    quote do
      unquote(memory_monitor())
      Mix.install([{:bandit, git: unquote(repo), ref: unquote(treeish)}])
      unquote(plug_def())
      Bandit.start_link(plug: BenchmarkPlug, options: [port: unquote(port)])
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp server_script(%{server: "bandit", treeish: treeish, port: port}) do
    quote do
      unquote(memory_monitor())
      Mix.install([{:bandit, github: "mtrudel/bandit", ref: unquote(treeish)}])
      unquote(plug_def())
      Bandit.start_link(plug: BenchmarkPlug, options: [port: unquote(port)])
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp server_script(%{server: "cowboy", treeish: treeish, port: port}) do
    quote do
      unquote(memory_monitor())
      Mix.install([{:plug_cowboy, github: "elixir-plug/plug_cowboy", ref: unquote(treeish)}])
      unquote(plug_def())
      Plug.Cowboy.http(BenchmarkPlug, [], port: unquote(port))
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp memory_monitor do
    quote do
      defmodule MemoryMonitor do
        @moduledoc false

        use GenServer

        def reset_stats, do: Process.list() |> Enum.map(&:erlang.garbage_collect/1)
        def record_stats, do: GenServer.cast(__MODULE__, {:record_stats, :erlang.memory()})
        def get_stats, do: GenServer.call(__MODULE__, :get_stats)

        def start_link(args) do
          GenServer.start_link(__MODULE__, args, name: __MODULE__)
        end

        def init(_) do
          {:ok, []}
        end

        def handle_cast({:record_stats, new_stats}, state), do: {:noreply, [new_stats | state]}

        def handle_call(:get_stats, _from, state) do
          result =
            state
            |> Enum.reduce(fn elem, acc ->
              elem
              |> Keyword.map(fn {k, v} -> max(v, acc[k]) end)
            end)
            |> Keyword.put(:count, length(state))
            |> Enum.map_join(", ", fn {k, v} -> "\"memory_#{k}\": #{v}" end)

          {:reply, "{#{result}}", state}
        end
      end

      MemoryMonitor.start_link(:ok)
    end
  end

  defp plug_def do
    quote do
      defmodule BenchmarkPlug do
        @moduledoc false

        import Plug.Conn

        @payload String.duplicate("a", 10_000)

        def init(opts), do: opts

        def call(%{path_info: ["noop"]} = conn, _opts) do
          MemoryMonitor.record_stats()
          send_resp(conn, 204, <<>>)
        end

        def call(%{path_info: ["upload"]} = conn, _opts) do
          {:ok, body, conn} = do_read_body(conn)
          MemoryMonitor.record_stats()
          send_resp(conn, 204, <<>>)
        end

        def call(%{path_info: ["download"]} = conn, _opts) do
          MemoryMonitor.record_stats()
          send_resp(conn, 204, @payload)
        end

        def call(%{path_info: ["echo"]} = conn, _opts) do
          {:ok, body, conn} = do_read_body(conn)
          MemoryMonitor.record_stats()
          send_resp(conn, 200, body)
        end

        def call(%{path_info: ["reset_stats"]} = conn, _opts) do
          MemoryMonitor.reset_stats()
          send_resp(conn, 200, "OK")
        end

        def call(%{path_info: ["stats"]} = conn, _opts) do
          send_resp(conn, 200, MemoryMonitor.get_stats())
        end

        def call(conn, _opts) do
          send_resp(conn, 404, "Not Found")
        end

        defp do_read_body(conn, body \\ []) do
          case read_body(conn) do
            {:ok, nil, conn} -> {:ok, body, conn}
            {:ok, new_body, conn} -> {:ok, [body | new_body], conn}
            {:more, new_body, conn} -> do_read_body(conn, [body | new_body])
          end
        end
      end
    end
  end
end

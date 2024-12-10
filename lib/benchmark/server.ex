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
    MuonTrap.Daemon.start_link("perf", ["record", "-o", "./perf.data", "--call-graph=fp", "--", "elixir", "--erl", "+JPperf true", "-e", server_script(server_def)],
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

      Mix.install([
        {:bandit, path: "../bandit", force: true, override: true},
        {:websock_adapter, "~> 0.4"}
      ])

      unquote(plug_def())
      Bandit.start_link(plug: BenchmarkPlug, port: unquote(port))
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp server_script(%{server: "bandit", repo: repo, treeish: treeish, port: port}) do
    quote do
      unquote(memory_monitor())

      Mix.install([
        {:bandit, git: unquote(repo), ref: unquote(treeish), force: true, override: true},
        {:websock_adapter, "~> 0.4"}
      ])

      unquote(plug_def())
      Bandit.start_link(plug: BenchmarkPlug, port: unquote(port))
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp server_script(%{server: "bandit", treeish: treeish, port: port}) do
    quote do
      unquote(memory_monitor())

      Mix.install([
        {:bandit, github: "mtrudel/bandit", ref: unquote(treeish), force: true, override: true},
        {:websock_adapter, "~> 0.4"}
      ])

      unquote(plug_def())
      Bandit.start_link(plug: BenchmarkPlug, port: unquote(port))
      Process.sleep(:infinity)
    end
    |> Macro.to_string()
  end

  defp server_script(%{server: "cowboy", treeish: treeish, port: port}) do
    quote do
      unquote(memory_monitor())

      Mix.install([
        {:plug_cowboy,
         github: "elixir-plug/plug_cowboy", ref: unquote(treeish), force: true, override: true},
        {:websock_adapter, "~> 0.4"}
      ])

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
          {:ok, %{}}
        end

        def handle_cast({:record_stats, new_stats}, state) do
          new_stats
          |> Enum.reduce(state, fn {k, v}, state ->
            Map.update(state, k, v, &max(&1, v))
          end)
          |> Map.update(:count, 1, &(&1 + 1))
          |> then(&{:noreply, &1})
        end

        def handle_call(:get_stats, _from, state) do
          state
          |> Enum.map_join(", ", fn {k, v} -> "\"memory_#{k}\": #{v}" end)
          |> then(&{:reply, "{#{&1}}", state})
        end
      end

      MemoryMonitor.start_link(:ok)
    end
  end

  defp plug_def do
    quote do
      defmodule WebSocketHandler do
        @payload String.duplicate("a", 10_000)

        def init("noop"), do: {:ok, "noop"}
        def init("upload"), do: {:ok, "upload"}
        def init("download"), do: {:ok, "download"}
        def init("echo"), do: {:ok, "echo"}
        def handle_in({_, _}, "download"), do: {:push, {:text, @payload}, "download"}
        def handle_in({msg, _}, "echo"), do: {:push, {:text, msg}, "echo"}
        def handle_in(_, state), do: {:ok, state}
        def handle_info(_, state), do: {:ok, state}
        def terminate(_, _), do: :ok
      end

      defmodule BenchmarkPlug do
        @moduledoc false

        import Plug.Conn

        @payload String.duplicate("a", 10_000)

        def init(opts), do: opts

        def call(%{path_info: ["noop"]} = conn, _opts) do
          send_resp(conn, 204, <<>>)
        end

        def call(%{path_info: ["upload"]} = conn, _opts) do
          {:ok, _body, conn} = do_read_body(conn)
          send_resp(conn, 204, <<>>)
        end

        def call(%{path_info: ["download"]} = conn, _opts) do
          send_resp(conn, 200, @payload)
        end

        def call(%{path_info: ["echo"]} = conn, _opts) do
          {:ok, body, conn} = do_read_body(conn)
          send_resp(conn, 200, body)
        end

        def call(%{path_info: ["websocket", action]} = conn, _opts) do
          WebSockAdapter.upgrade(conn, WebSocketHandler, action, [])
        end

        def call(%{path_info: ["memory_noop"]} = conn, _opts) do
          MemoryMonitor.record_stats()
          send_resp(conn, 204, <<>>)
        end

        def call(%{path_info: ["memory_upload"]} = conn, _opts) do
          {:ok, _body, conn} = do_read_body(conn)
          MemoryMonitor.record_stats()
          send_resp(conn, 204, <<>>)
        end

        def call(%{path_info: ["memory_download"]} = conn, _opts) do
          MemoryMonitor.record_stats()
          send_resp(conn, 200, @payload)
        end

        def call(%{path_info: ["memory_echo"]} = conn, _opts) do
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

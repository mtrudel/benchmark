defmodule WebSocketClientWorker do
  import Kernel, except: [send: 2]

  def run(_num, arg) do
    do_run(arg, arg.count, %{})
  end

  defp do_run(_arg, 0, state), do: state

  defp do_run(arg, count, state) do
    start_time = :os.perf_counter()
    {success, failure} = if do_connection(arg), do: {1, 0}, else: {0, 1}
    end_time = :os.perf_counter()
    duration = :erlang.convert_time_unit(end_time - start_time, :perf_counter, :microsecond)

    state =
      state
      |> Map.update(:min, duration, &min(&1, duration))
      |> Map.update(:max, duration, &max(&1, duration))
      |> Map.update(:sum, duration, &(&1 + duration))
      |> Map.update(:successful, success, &(&1 + success))
      |> Map.update(:failed, failure, &(&1 + failure))
      |> Map.update(:count, 1, &(&1 + 1))

    Process.sleep(1)

    do_run(arg, count - 1, state)
  end

  defp do_connection(%{endpoint: "noop"} = arg) do
    {:ok, client} = connect(arg.hostname, arg.port, arg.endpoint)
    close(client)
    true
  end

  defp do_connection(%{endpoint: "upload"} = arg) do
    {:ok, client} = connect(arg.hostname, arg.port, arg.endpoint)
    {:ok, client} = send(arg.upload, client)
    close(client)
    true
  end

  defp do_connection(%{endpoint: "download"} = arg) do
    {:ok, client} = connect(arg.hostname, arg.port, arg.endpoint)
    {:ok, client} = send("a", client)
    {:ok, _data, client} = recv(client)
    close(client)
    true
  end

  defp do_connection(%{endpoint: "echo"} = arg) do
    {:ok, client} = connect(arg.hostname, arg.port, arg.endpoint)
    {:ok, client} = send(arg.upload, client)
    {:ok, _data, client} = recv(client)
    close(client)
    true
  end

  defp connect(hostname, port, endpoint) do
    {:ok, conn} =
      Mint.HTTP.connect(:http, hostname, port, transport_opts: [nodelay: true, timeout: 60_000])

    {:ok, conn, ref} = Mint.WebSocket.upgrade(:ws, conn, "/websocket/#{endpoint}", [])
    message = receive(do: (message -> message))

    {:ok, conn, [{:status, ^ref, status}, {:headers, ^ref, resp_headers}, {:done, ^ref}]} =
      Mint.WebSocket.stream(conn, message)

    {:ok, conn, websocket} = Mint.WebSocket.new(conn, ref, status, resp_headers)
    {:ok, {conn, websocket, ref}}
  end

  defp send(data, {conn, websocket, ref}) do
    {:ok, websocket, data} = Mint.WebSocket.encode(websocket, {:text, data})
    {:ok, conn} = Mint.WebSocket.stream_request_body(conn, ref, data)
    {:ok, {conn, websocket, ref}}
  end

  defp recv({conn, websocket, ref}) do
    message = receive(do: (message -> message))
    {:ok, conn, [{:data, ^ref, data}]} = Mint.WebSocket.stream(conn, message)
    {:ok, websocket, [{:text, data}]} = Mint.WebSocket.decode(websocket, data)
    {:ok, data, {conn, websocket, ref}}
  end

  defp close({conn, websocket, ref}) do
    {:ok, websocket, data} = Mint.WebSocket.encode(websocket, :close)
    {:ok, conn} = Mint.WebSocket.stream_request_body(conn, ref, data)
    message = receive(do: (message -> message))
    {:ok, conn, [{:data, ^ref, data}]} = Mint.WebSocket.stream(conn, message)
    {:ok, _websocket, _frames} = Mint.WebSocket.decode(websocket, data)
    Mint.HTTP.close(conn)
  end
end

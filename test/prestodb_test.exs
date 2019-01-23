defmodule PrestodbTest do
  use ExUnit.Case

  setup do
    [bypass: Bypass.open(port: 8123)]
  end

  describe "when given a single response" do
    setup %{bypass: bypass} do
      Bypass.expect(bypass, "POST", "/v1/statement", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert "select * from users" == body

        presto_response(conn,
          state: "FINISHED",
          columns: ["id", "name"],
          data: [
            [1, "Brian"],
            [2, "Shannon"]
          ]
        )
      end)

      :ok
    end

    test "can execute a query and return data as enumerable" do
      result =
        Prestodb.execute("select * from users") |> Enum.map(fn [id, name] -> {id, name} end)

      assert result == [{1, "Brian"}, {2, "Shannon"}]
    end

    test "can execute a query and access data as map" do
      result =
        Prestodb.execute("select * from users", by_names: true)
        |> Enum.map(fn row -> {row["id"], row["name"]} end)

      assert result == [{1, "Brian"}, {2, "Shannon"}]
    end
  end

  test "sends transformed headers to presto", %{bypass: bypass} do
    Bypass.expect(bypass, "POST", "/v1/statement", fn conn ->
      assert ["hive"] == Plug.Conn.get_req_header(conn, "x-presto-catalog")
      assert ["people"] == Plug.Conn.get_req_header(conn, "x-presto-schema")
      assert ["session value"] == Plug.Conn.get_req_header(conn, "x-presto-session")

      presto_response(conn,
        columns: ["id", "name"],
        data: [
          [1, "Brian"],
          [2, "Shannon"]
        ]
      )
    end)

    Prestodb.execute("select * from users",
      catalog: "hive",
      schema: "people",
      session: "session value"
    )
  end

  describe "when given a multi document response" do
    setup %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/statement", fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert "select * from users" == body

        presto_response(conn,
          state: "QUEUED",
          next_uri: "/request1",
          columns: ["id", "name"],
          data: [
            [1, "Tyler"],
            [2, "Walter"]
          ]
        )
      end)

      Bypass.expect_once(bypass, "GET", "/request1", fn conn ->
        presto_response(conn, state: "PLANNING", next_uri: "/request2")
      end)

      Bypass.expect_once(bypass, "GET", "/request2", fn conn ->
        presto_response(conn,
          state: "FINISHED",
          columns: ["id", "name"],
          data: [
            [3, "Londyn"],
            [4, "Sophie"]
          ]
        )
      end)

      :ok
    end

    test "works when enumerated over" do
      result =
        Prestodb.execute("select * from users")
        |> Enum.map(fn [id, name] -> {id, name} end)

      assert result == [
               {1, "Tyler"},
               {2, "Walter"},
               {3, "Londyn"},
               {4, "Sophie"}
             ]
    end

    test "works when enumerated over by names" do
      result =
        Prestodb.execute("select * from users", by_names: true)
        |> Enum.map(fn row -> {row["id"], row["name"]} end)

      assert result == [
               {1, "Tyler"},
               {2, "Walter"},
               {3, "Londyn"},
               {4, "Sophie"}
             ]
    end

    test "can all be fetched at once" do
      result = Prestodb.execute("select * from users") |> Prestodb.prefetch()

      assert result == [
               [1, "Tyler"],
               [2, "Walter"],
               [3, "Londyn"],
               [4, "Sophie"]
             ]
    end

    test "can all be fetched and mapped by name" do
      result = Prestodb.execute("select * from users", by_names: true) |> Prestodb.prefetch()

      assert result == [
               %{"id" => 1, "name" => "Tyler"},
               %{"id" => 2, "name" => "Walter"},
               %{"id" => 3, "name" => "Londyn"},
               %{"id" => 4, "name" => "Sophie"}
             ]
    end
  end

  test "requests are retried if a http status 503 is returned", %{bypass: bypass} do
    {:ok, pid} = Agent.start_link(fn -> 1 end)

    Bypass.expect_once(bypass, "POST", "/v1/statement", fn conn ->
      presto_response(conn,
        next_uri: "/request1",
        state: "QUEUED",
        columns: ["id", "name"],
        data: [
          [1, "Tyler"],
          [2, "Walter"]
        ]
      )
    end)

    Bypass.expect(bypass, "GET", "/request1", fn conn ->
      case Agent.get_and_update(pid, fn s -> {s, s + 1} end) do
        1 ->
          Plug.Conn.resp(conn, 503, "Service Unavailable")

        _n ->
          presto_response(conn,
            state: "FINISHED",
            columns: ["id", "name"],
            data: [
              [3, "Londyn"],
              [4, "Sophie"]
            ]
          )
      end
    end)

    result = Prestodb.execute("select * from users") |> Prestodb.prefetch()

    assert result == [
             [1, "Tyler"],
             [2, "Walter"],
             [3, "Londyn"],
             [4, "Sophie"]
           ]
  end

  defp presto_response(conn, opts) do
    body = %{
      "stats" => %{"state" => Keyword.get(opts, :state, "FINISHED")},
      "columns" => Keyword.get(opts, :columns, []) |> Enum.map(fn col -> %{"name" => col} end),
      "data" => Keyword.get(opts, :data, []),
      "nextUri" => Keyword.get(opts, :next_uri)
    }

    Plug.Conn.put_resp_header(conn, "content-type", "application/json")
    |> Plug.Conn.resp(200, Jason.encode!(body))
  end
end

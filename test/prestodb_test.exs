defmodule PrestodbTest do
  use ExUnit.Case

  import Tesla.Mock

  describe "Prestodb.execute" do
    test "can execute a query and access rows" do
      mock fn
        %{method: :post, url: "http://prestodb.test/v1/statement", body: "select * from people"} ->
          json(%{
            "stats" => %{"state" => "FINISHED"},
            "columns" => [%{"name" => "id"}, %{"name" => "name"}],
            "data" => [
              [1, "Brian"],
              [2, "Shannon"]
            ]
          })
      end

      result =
        Prestodb.execute("select * from people")
        |> Enum.map(fn [id, name] -> {id, name} end)

      assert MapSet.new(result) == MapSet.new([{1, "Brian"}, {2, "Shannon"}])
    end

    test "can execute query and access rows by name" do
      mock fn
        %{method: :post, url: "http://prestodb.test/v1/statement", body: "select * from people"} ->
          json(%{
            "stats" => %{"state" => "FINISHED"},
            "columns" => [%{"name" => "id"}, %{"name" => "name"}],
            "data" => [
              [1, "Tyler"],
              [2, "Walter"]
            ]
          })
      end

      result =
        Prestodb.execute("select * from people", by_names: true)
        |> Enum.map(fn row -> {row["id"], row["name"]} end)

      assert MapSet.new(result) == MapSet.new([{1, "Tyler"}, {2, "Walter"}])
    end

    test "sends optional headers to prestodb" do
      mock fn
        %{
          method: :post,
          url: "http://prestodb.test/v1/statement",
          body: "select * from users",
          headers: headers
        } ->
          assert {"X-Presto-Catalog", "memory"} in headers
          assert {"X-Presto-Schema", "default"} in headers

          json(%{
            "stats" => %{"state" => "FINISHED"},
            "columns" => [%{"name" => "id"}, %{"name" => "name"}],
            "data" => [
              [1, "Tyler"],
              [2, "Walter"]
            ]
          })
      end

      result = Prestodb.execute("select * from users", catalog: "memory", schema: "default")
      assert Enum.count(result) == 2
    end

    test "execute supports multi document responses" do
      mock fn
        %{method: :post, url: "http://prestodb.test/v1/statement", body: "select * from users"} ->
          json(%{
            "nextUri" => "http://prestodb.test/request1",
            "stats" => %{"state" => "QUEUED"},
            "columns" => [%{"name" => "id"}, %{"name" => "name"}],
            "data" => [
              [1, "Tyler"],
              [2, "Walter"]
            ]
          })

        %{method: :get, url: "http://prestodb.test/request1"} ->
          json(%{
            "nextUri" => "http://prestodb.test/request2",
            "stats" => %{"state" => "PLANNING"}
          })

        %{method: :get, url: "http://prestodb.test/request2"} ->
          json(%{
            "stats" => %{"state" => "QUEUED"},
            "columns" => [%{"name" => "id"}, %{"name" => "name"}],
            "data" => [
              [3, "Londyn"],
              [4, "Sophie"]
            ]
          })

          result =
            Prestodb.execute("select * from users")
            |> Enum.result(fn [id, name] -> {id, name} end)

          assert result == [
                   {1, "Tyler"},
                   {2, "Walter"},
                   {3, "Londyn"},
                   {4, "Sophie"}
                 ]
      end
    end
  end
end

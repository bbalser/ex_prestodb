defmodule PrestodbTest do
  use ExUnit.Case

  import Tesla.Mock

  test "something" do

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

    result = Prestodb.execute("select * from people")
    |> Enum.map(fn row -> {row["id"], row["name"]} end)

    assert MapSet.new(result) == MapSet.new([{1, "Brian"}, {2, "Shannon"}])

  end

end

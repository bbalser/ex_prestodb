ExUnit.start()
Application.ensure_all_started(:bypass)

Mox.defmock(Prestodb.Tesla.Mock, for: Tesla.Adapter)

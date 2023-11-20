ExUnit.start()

{:ok, registry} = Registry.start_link(keys: :unique, name: OrangeCheckr.TestRegistry)

ExUnit.after_suite(fn _ -> Process.exit(registry, :shutdown) end)

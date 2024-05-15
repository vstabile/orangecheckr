import Config

config :orangecheckr, :proxy_host, "b944-2001-8a0-6034-4300-241c-d9d1-a796-bf69.ngrok-free.app"
config :orangecheckr, :proxy_port, 4000
config :orangecheckr, :proxy_path, "/"

config :orangecheckr, :bot_nsec, "nsec1mysfdmg2v4wxc95m57463eh6aclj5ph553lzml87u5mtqajyqffqer7ks4"
config :orangecheckr, :bot_name, "OrangeCheckr Bot"

config :orangecheckr, :relay_uri, "ws://localhost:8080/"
config :orangecheckr, :favicon_path, "/favicon.ico"

env_config = "#{Mix.env()}.exs"

if File.exists?("config/#{env_config}") do
  import_config env_config
end

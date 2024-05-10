import Config

config :orangecheckr, :proxy_host, "b944-2001-8a0-6034-4300-241c-d9d1-a796-bf69.ngrok-free.app"
config :orangecheckr, :proxy_port, 4000
config :orangecheckr, :proxy_path, "/"
config :orangecheckr, :favicon_path, "/favicon.ico"
config :orangecheckr, :relay_uri, "ws://localhost:8080/"

env_config = "#{Mix.env()}.exs"

if File.exists?("config/#{env_config}") do
  import_config env_config
end

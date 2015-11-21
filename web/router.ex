defmodule Hue2.Router do
        use Hue2.Web, :router

        pipeline :browser do
                plug :accepts, ["html"]
                plug :fetch_session
                plug :fetch_flash
                plug :protect_from_forgery
                plug :put_secure_browser_headers
        end

        scope "/", Hue2 do
                pipe_through :browser # Use the default browser stack
                get "/", PageController, :index
        end
        
        scope "/rss", Hue2 do
                get "/", FeedController, :index
        end
 
end

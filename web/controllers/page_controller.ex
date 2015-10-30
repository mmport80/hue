defmodule Hue2.PageController do

        use Hue2.Web, :controller

        def index(conn, _params) do
                tweets = Hue2.TweetInfo.start()
                render conn, "index.html", tweets: tweets
        end
end

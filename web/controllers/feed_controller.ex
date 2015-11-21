defmodule Hue2.FeedController do  
        use Hue2.Web, :controller
        alias Hue2.Entry

        def index(conn, _params) do
                entries = Repo.all from e in Entry, order_by: [desc: e.id], preload: [:user]
                conn
                |> put_layout(:none)
                |> put_resp_content_type("application/xml")
                |> render "index.xml", items: entries
        end
        
        def index(conn, _params) do
                articles = Hue2.TweetInfo2.get_articles()
                render conn, "index.html", articles: articles
        end
end  

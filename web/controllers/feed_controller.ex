defmodule Hue2.FeedController do
        use Hue2.Web, :controller
        alias Hue2.Article

        def index(conn, _params) do
                articles = Hue2.GetArticles.get_articles()

                conn
                |> put_layout(:none)
                |> put_resp_content_type("application/xml")
                |> render("index.xml", articles: articles)

        end
end

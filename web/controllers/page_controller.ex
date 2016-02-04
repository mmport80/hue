defmodule Hue2.PageController do

        use Hue2.Web, :controller

        def index(conn, _params) do
                articles = Hue2.GetArticles.get_articles_for_website()
                render conn, "index.html", articles: articles
        end
end

defmodule Hue2.GetArticles do
  alias Hue2.Repo
  alias Hue2.Article

  import Ecto.Query

  def get_articles() do
    [show: n] = Application.get_env( :hue2, :settings )

    #sql query
    Article
      |> where(
        [a],
        a.inserted_at > datetime_add(^Ecto.DateTime.utc, -1, "day")
        )
      |> Repo.all
      #filter out articles which have videos etc which we do not currently support
      |> Enum.filter(
        fn(article) ->
          article.partial == false
        end
      )
      |> order
      |> remove_dupes
      |> Enum.take(n)
  end

  defp order(articles) do
    articles
    |> Enum.sort_by(
      fn(article) ->
        100000 * ( max(article.favorite_count - 1, 0) + max(article.retweet_count - 1, 0) * 1.49 ) / article.followers_count
      end
    )
  end

  defp remove_dupes(articles) do
    articles
    |> Enum.reduce(
      [],
      fn(article, acc) ->
        #if tweetid already in don't include anymore
        cond do
          acc
          |> Enum.filter(
            fn(a) ->
              #id or text is the same...
              (a.tweet_id_str == article.tweet_id_str) || (a.text == article.text)
            #if end up with nothing
            end ) == [] ->
              [article|acc]
          true ->
            acc
        end
      end
    )
  end
end

defmodule Hue2.GetArticles do
  alias Hue2.Repo
  alias Hue2.Article

  import Ecto.Query

################################################################################################
#if quality isn't good enough
#add a day component
#look back more than 1 days

  def get_articles_for_website() do
    [show: n]         = Application.get_env( :hue2, :settings )

    get_articles(1)
      #filter in tweets for website with either picture or title
      |> Enum.filter(
        fn(article) ->
          article.title != nil || article.media_url != nil
        end
      )
      |> Enum.take(n)
  end

################################################################################################

  def get_articles_for_twitter_feed() do
    [show: n]         = Application.get_env( :hue2, :settings )

    get_articles(1)
      #no filters
      |> Enum.take(n)

  end

################################################################################################
  #lookback x days
  defp get_articles(days) do
    #sql query
    Article
      |> where(
        [a],
        a.inserted_at > datetime_add(^Ecto.DateTime.utc, ^(-1 * days), "day")
        )
      |> Repo.all
      |> order
      |> remove_dupes
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

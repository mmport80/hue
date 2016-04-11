defmodule Hue2.GetArticles do
  alias Hue2.Repo
  alias Hue2.Article

  import Ecto.Query

################################################################################################
#if quality isn't good enough
#add a day component
#look back more than 1 days

  @spec get_articles_for_website() :: list( %Article{} )
  def get_articles_for_website() do
    [show: n] = Application.get_env( :hue2, :settings )

    get_articles()
      #filter in tweets for website with either picture or title
      |> Enum.filter(
        fn(article) ->
          article.title != nil || article.media_url != nil
        end
      )
      |> Enum.take(n)
  end

################################################################################################

  @spec get_articles_for_twitter_feed() :: list( %Article{} )
  def get_articles_for_twitter_feed() do
    [show: n] = Application.get_env( :hue2, :settings )
    get_articles()
      #no filters
      |> Enum.take(n)
  end

################################################################################################
  #lookback x days
  @spec get_articles() :: list( %Article{} )
  defp get_articles() do
    #sql query
    Article
      |> where(
        [a],
        #-1 * 1 = one day ago
        a.inserted_at > datetime_add(^Ecto.DateTime.utc, ^(-1 * 1), "day")
        )
      |> Repo.all
      |> order
      |> remove_dupes
  end

  @spec order( list( %Article{} ) ) :: list( %Article{} )
  defp order(articles) do
    articles
    |> Enum.sort_by(
      fn(article) ->
        #-1 or not?
        #w extra 61 multiplier, try to do with out
        fav = article.favorite_count
        rtw = article.retweet_count
        fol = article.followers_count
        #61 is an active user's median number of followers
        #mean is much higher, but median is less onerous on users with fewer followers
        #denominator tries to approx total audience of tweet
        #of course the number of ppl who actually see a tweet is a fraction of the whole...
        #but perhaps the actual audience as a ratio of total possible audience is more or less constant
        #therefore it washes out in the end...

        #perhaps there's another field which shows how many ppl have actually seen a tweet?!?!

        #(faves + retweets) / (followers + 60 * retweets)

        #on average 1.5 faves ~= 1 retweet, i.e. 50% more likely to see faves

        #todo: add time since original tweet was published
        #longer the time, expect more faves + retweets
        #tweet authored time minus snapshot when we see it (inserted time, in db?)

        #longer time means greater actual audience and also more faves + retweets...
        #how does this ratio grow over time?
        #record, and then regress against ratio here
        #take the result and multiply it aginst ratio
        #then multiply total time against everything

        ( fav + rtw * 1.49 ) / ( fol + rtw * 61 )
      end
    )
  end

  @spec remove_dupes( list( %Article{} ) ) :: list( %Article{} )
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

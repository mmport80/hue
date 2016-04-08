defmodule Hue2.Retweet do
  import Hue2.GetArticles

  #get articles
  #retweet
  @spec retweet() :: nil
  def retweet() do
    #what's already been tweeted
    htl = ExTwitter.user_timeline(count: 200)
      |> Enum.filter(
        fn(t) -> t.quoted_status != nil
        end)
      |> Enum.map(
        fn(t) -> t.quoted_status.id_str
        end)

    get_articles_for_twitter_feed()
      #map with index or reduce
      |> Enum.reduce(
        0,
        fn(a, acc) ->
          cond do
            #check whether article has already been retweeted
            Enum.member?(htl, a.tweet_id_str) ->
              #do nothing
              acc + 1
            true ->
              #tweet so many stars / top daily pick
              #append add link to orig tweet
              origTweetLink = "https://twitter.com/" <> a.tweet_author <> "/status/" <> a.tweet_id_str

              #star emoticon in binary
              star = <<11088 :: utf8>>

              #rate posts by stars etc
              rating =
                cond do
                  acc > 6 ->
                    star
                  acc > 3 ->
                    star <> star
                  acc > 0 ->
                    star <> star <> star
                  true ->
                    "~Top Daily Pick~"
                end

              IO.inspect a.referrers

              #reduce referrers int "\nh/t @xoxo, @yoyo"
              referrers = referrer_string(a.referrers)
              s = rating <> " " <> referrers <> " " <> origTweetLink

              #tweet rating and link to original tweet
              _ = ExTwitter.update(s)

              #print for testing
              #IO.puts s

              acc + 1
          end
        end
      )
  end

  @spec referrer_string( list( char_list ) ) :: binary
  defp referrer_string(referrers) do
    cond do
      referrers != [] && referrers != nil ->
        referrer_string = referrers
          #add @s
          |> Enum.map(
            fn(referrer) ->
              "@" <> referrer
            end
          )
          #concatenate with ,s
          |> Enum.reduce(
            fn(referrer, acc) ->
              acc <> ", "  <> referrer
            end
          )
        "\n\nh/t " <> referrer_string
       true ->
        ""
    end
  end
end

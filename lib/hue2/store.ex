defmodule Hue2.Store do
  alias Hue2.Repo
  alias Hue2.Article

  ##################################################################
  #get and store article data
  #every function accepts and returns an article object and a tweet

  @spec store() :: list ( {:ok, Ecto.Schema.t} | {:error, Ecto.Changeset.t} )
  def store() do
    #increase and reduce frequency -> hopefully avoid crashing bringing everything down...
    ExTwitter.home_timeline([count: 50])
      #recursively find relevant tweets if need be
      |> Stream.map(
        fn(tweet) ->
          #use original quoted or retweeted tweet if a quote or a retweet
          get_quoted_or_rtwd_status?(tweet, 0, [])
        end
      )
      #filter out tweets with zero faves & retweets
      |> Stream.filter(
        fn( %{ tweet: tweet, current_followers: _, referrers: _  } ) ->
          tweet.favorite_count > 1 || tweet.retweet_count > 1
        end
      )
      #map / setup
      #creates augmented article objects
      |> Stream.map(
        fn(tweet) ->
          tweet
          |> init
          #get external url
          |> get_expanded_url
          #get 'local' media url
          #|> get_local_media_url
          #pull everything from source website
          |> get_source_data
        end
      )
      #return only the articles
      |> Stream.map(
        fn( %{tweet: %ExTwitter.Model.Tweet{} = _, article: %Hue2.Article{} = article} ) ->
          article
        end
      )
      #only store tweets with a link
      #change this? best not...
      |> Stream.filter(
        fn(article) ->
          #don't save anything without a url
          #don't retweet own tweets
          article.expanded_url != nil && ( article.referrers |> Enum.all?( fn(b) -> b != "huebrent1" end ) )
        end
      )
      #update db
      |> Enum.map(
        fn( article ) ->
          Repo.insert(article)
        end
      )
  end

  #recursively find original tweet
  @spec get_quoted_or_rtwd_status?( %ExTwitter.Model.Tweet{}, integer, list(char_list) ) :: %{ tweet: %ExTwitter.Model.Tweet{}, current_followers: integer, referrers: list(char_list) }
  defp get_quoted_or_rtwd_status?( %ExTwitter.Model.Tweet{} = tweet, followers, referrers ) do
    #add up followers, try to count up total tweet audience
    #collect user names along the way for H/Ts
    cond do
      tweet.retweeted_status != nil ->
        tweet.retweeted_status.id
          |> ExTwitter.show
          |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
      true ->
          #update followers with total countable (approx) audience
          %{ tweet: tweet, current_followers: followers, referrers: Enum.uniq(referrers) }
    end
  end

  #template
  #defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
  #        %{tweet: tweet, article: article}
  #end

  #####################################################################

  @spec init( %{tweet: %ExTwitter.Model.Tweet{}, current_followers: integer, referrers: list(char_list) } ) :: %{ tweet: %ExTwitter.Model.Tweet{}, article: %Article{} }
  defp init( %{ tweet: tweet, current_followers: current_followers, referrers: referrers } ) do
    #take array of refers
    #insert array into hters table
    #

    {:ok, ca_t} = Timex.parse(tweet.created_at, "%a %b %d %H:%M:%S %z %Y", :strftime)
    {:ok, ca_e} = Ecto.DateTime.load({{ca_t.year,ca_t.month,ca_t.day},{ca_t.hour,ca_t.minute,ca_t.second}})

    article = %Article{
      media_url:              nil,
      #don't use tweet test anymore here, just pop with og desc from now on
      text:                   nil,
      expanded_url:           nil,
      title:                  nil,
      favorite_count:         tweet.favorite_count,
      retweet_count:          tweet.retweet_count,
      #total audience approximation
      followers_count:        tweet.user.followers_count + current_followers,
      #switch to quoted
      partial:                false,
      tweet_id_str:           tweet.id_str,
      tweet_author:           tweet.user.screen_name,
      referrers:              referrers,
      tweet_created_at:       ca_e
      }
    %{tweet: tweet, article: article}
  end

  #####################################################################

  @spec get_expanded_url( %{tweet: %ExTwitter.Model.Tweet{}, article: %Article{} } ) :: %{tweet: %ExTwitter.Model.Tweet{}, article: %Article{} }
  defp get_expanded_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
    vanilla_return = %{tweet: tweet, article: article}
    cond do
      has_source_url?(tweet) ->
        [first_urls|_] = tweet.entities.urls
        %{ vanilla_return | article: %Article{ article | expanded_url: first_urls.expanded_url } }
      true ->
        vanilla_return
    end
  end

  @spec has_source_url?( %ExTwitter.Model.Tweet{} ) :: boolean
  defp has_source_url?( %ExTwitter.Model.Tweet{}=tweet ) do
    Map.has_key?(tweet.entities, :urls)
    && Enum.any?(tweet.entities.urls)
  end

  #####################################################################

  @spec get_source_data(  %{tweet: %ExTwitter.Model.Tweet{}, article: %Article{} }  ) :: %{tweet: %ExTwitter.Model.Tweet{}, article: %Article{} }
  defp get_source_data( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
    vanilla_return = %{tweet: tweet, article: article}

    #tmblr causes hackney to crash...
    bad_urls = [
      "http://tmblr.co/",
      "https://tmblr.co/",
      "http://bit.ly/1QW182g"
      ]

    cond do
      #due to hackney bug
      article.expanded_url == nil || String.starts_with?(article.expanded_url, bad_urls) ->
        vanilla_return
      true ->
        #spawn so that crashes won't bring everything down
        case HTTPoison.get(article.expanded_url, [], [ hackney: [follow_redirect: true] ]) do
          #prob paywalled
          {:error, %HTTPoison.Error{reason: reason} } ->
            IO.inspect reason
            vanilla_return
          {:ok, http} ->
            cond do
              #in case link goes to a pdf or something
              String.valid?(http.body) ->
                #gotta figure out how to do this better - maybe pipes???
                media_url = http.body |> Floki.find("meta[property='og:image']") |> Floki.attribute("content") |> List.first

                if media_url != nil && media_url != "" do
                  article = %Article{ article | media_url: media_url }
                end

                title = http.body |> Floki.find("meta[property='og:title']") |> Floki.attribute("content") |> List.first

                if title != nil && title != "" do
                  article = %Article{ article | title: String.slice(title,0,255) }
                end

                description = http.body |> Floki.find("meta[property='og:description']") |> Floki.attribute("content") |> List.first

                if description != nil && description != "" do
                  article = %Article{ article | text: String.slice(description,0,999) }
                end

                #return last value
                %{tweet: tweet, article: article}
              #link to PDF / PPT etc
              true ->
                vanilla_return
            end
          _ ->
            IO.puts "something else happened"
            vanilla_return
        end
    end
  end
end

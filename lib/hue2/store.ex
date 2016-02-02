defmodule Hue2.Store do
  alias Hue2.Repo
  alias Hue2.Article

  ##################################################################
  #get and store article data
  #every function accepts and returns an article object and a tweet

  def store() do
    #increase and reduce frequency -> hopefully avoid crashing bringing everything down...
    ExTwitter.home_timeline([count: 20])
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
          |> get_local_media_url
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
      |> Stream.filter(
        fn(article) ->
          article.expanded_url != nil
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
  defp get_quoted_or_rtwd_status?( %ExTwitter.Model.Tweet{} = tweet, followers, referrers ) do
    #add up followers, try to count up total tweet audience
    #collect user names along the way for H/Ts
    cond do
      tweet.retweeted_status == nil && tweet.quoted_status == nil && tweet.in_reply_to_status_id_str == nil ->
        #update followers with total countable (approx) audience
        %{ tweet: tweet, current_followers: followers, referrers: Enum.uniq(referrers) }
      tweet.quoted_status != nil ->
        tweet.quoted_status.id
          |> ExTwitter.show
          |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
      tweet.retweeted_status != nil ->
        tweet.retweeted_status.id
          |> ExTwitter.show
          |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
      true ->
        tweet.in_reply_to_status_id_str
          |> ExTwitter.show
          |> get_quoted_or_rtwd_status?( followers + tweet.user.followers_count, [ tweet.user.screen_name | referrers ] )
    end
  end

  #template
  #defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
  #        %{tweet: tweet, article: article}
  #end

  #####################################################################

  defp init( %{ tweet: tweet, current_followers: current_followers, referrers: referrers  } ) do
    #take array of refers
    #insert array into hters table
    #
    article = %Article{
      media_url:              nil,
      text:                   tweet.text,
      expanded_url:           nil,
      title:                  nil,
      favorite_count:         tweet.favorite_count,
      retweet_count:          tweet.retweet_count,
      #total audience approximation
      followers_count:        tweet.user.followers_count + current_followers,
      partial:                false,
      tweet_id_str:           tweet.id_str,
      tweet_author:           tweet.user.screen_name,
      referrers:              referrers
      }
    %{tweet: tweet, article: article}
  end

  #####################################################################

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

  defp has_source_url?( %ExTwitter.Model.Tweet{}=tweet ) do
    Map.has_key?(tweet.entities, :urls)
    && Enum.any?(tweet.entities.urls)
    && (
      url = tweet.entities.urls |> List.first
      !String.match?( url.display_url, ~r/vine.co/ )
    )
  end

  #####################################################################

  defp get_local_media_url( %{tweet: %ExTwitter.Model.Tweet{} = tweet, article: %Article{} = article} ) do
    vanilla_return = %{tweet: tweet, article: article}

    cond do
      #has media and has photos
      Map.has_key?(tweet.entities, :media) ->
        cond do
          #has video, tweet is partial (do not support video right now)
          Enum.any?( videos(tweet) ) ->
            %{ vanilla_return | article:  %Article{ article | partial: true } }
          #has many photos, update partial - don't support multiple photo tweets
          tweet |> photos |> length > 1 ->
            %{ vanilla_return | article:  %Article{ article | partial: true } }
          #has single photo
          tweet |> photos |> length == 1 ->
            %{ vanilla_return | article:  %Article{ article | media_url: first_photo(tweet).media_url } }
          true ->
            vanilla_return
        end
      true ->
        vanilla_return
    end
  end

  defp videos(%ExTwitter.Model.Tweet{}=tweet) do
    tweet.entities.media
      |> Enum.filter(
        fn(medium) ->
          !String.match?(medium.media_url, ~r/ext_tw_video_thumb/)
        end
      )
  end

  defp photos(%ExTwitter.Model.Tweet{}=tweet) do
    tweet.entities.media
      |> Enum.filter(
        fn(medium) ->
          medium.type == "photo"
        end
      )
  end

  defp first_photo(%ExTwitter.Model.Tweet{}=tweet) do
    photos(tweet) |> hd
  end

  #####################################################################

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

                if media_url != nil do
                  article = %Article{ article | media_url: media_url }
                end

                title = http.body |> Floki.find("meta[property='og:title']") |> Floki.attribute("content") |> List.first

                if title != nil do
                  article = %Article{ article | title: String.slice(title,0,255) }
                end

                description = http.body |> Floki.find("meta[property='og:description']") |> Floki.attribute("content") |> List.first

                if description != nil do
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

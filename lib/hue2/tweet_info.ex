
defmodule Hue2.TweetInfo do
        alias Hue2.Repo
        alias Hue2.Article

        import Timex
        import Ecto.Query
        
        def get_articles() do
                Article 
                |> select([c,_], c ) 
                |> Hue2.Repo.all 
                |> less_than_a_day_old
                |> order
                |> remove_dupes
                |> Enum.take(10)
                #sort desc
                #more followers bad
                #more faves & rtwts good
        end
        
        defp order(articles) do
                articles
                |> Enum.sort_by(
                        fn(article) ->
                                article.followers_count / (1 + article.favorite_count + article.retweet_count * 2)
                        end 
                )
        end
        
        
        defp less_than_a_day_old(articles) do
                articles
                |> Enum.filter(
                        fn(article) -> 
                                Timex.Date.diff(
                                        convert_ecto_to_timex(article.inserted_at),
                                        Timex.Date.local(),
                                        :days
                                        )
                                <= 1
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
                                                        (a.tweet_id_str == article.tweet_id_str)
                                                end        
                                        ) == [] ->
                                                [article|acc]
                                        true ->
                                                acc
                                end
                        end
                )
        end
        
        #convert ecto date datetime to timex datetime
        #find diff in days
        
        def convert_ecto_to_timex(ecto_dt) do
                #to tuple
                {:ok, tuple_dt} = Ecto.DateTime.dump(ecto_dt)
                Timex.Date.from(tuple_dt)
        end
        
        
        
        
        #run every 15 mins
        #get and store article data
        def store() do
                ExTwitter.home_timeline([count: 200])
                        #retweets don't have a bunch of required data
                        #i.e. favourite_count and original tweet user
                        #this filters 'em out while extwitter doesn't support the retweeted_status field
                        
                        
                        #if a tweet doesn't have a retweet tag, but doesn have a retweet count
                        #something's not right => i.e. this tweet's a retweet! 
                        |> Enum.filter(
                                fn(tweet) ->
                                        #original tweet rtwt count?
                                        #trying to filter out retweets without retweeted status field
                                        !(
                                                #current tweet retweeted?
                                                (!tweet.retweeted == false && tweet.retweet_count > 0)  
                                                ||
                                                #begins with 'RT'
                                                String.starts_with?(tweet.text, "RT") 
                                        )
                                end
                        )
                        
                        #filters relevant tweets
                        #creates augmented article objects
                        |> Enum.reduce(
                                [],
                                fn(tweet, acc) ->
                                        cond do 
                                                #does tweet redirect elsewhere?
                                                has_source_url?(tweet) ->
                                                        get_source_url_info(tweet, acc)
                                                #does tweet contain a photo?
                                                has_photos?(tweet) ->
                                                        get_media_tweet_info( tweet, acc )
                                                true ->
                                                        acc
                                        end
                                end                                                                      
                        )
                        |> order
                        |> Enum.take(10)
                        |> Enum.map(
                                fn(article) ->
                                        #IO.inspect article
                                        Repo.insert(article)
                                end 
                        )
                        
        end
        
                
        
        defp get_source_url_info( %ExTwitter.Model.Tweet{}=tweet, acc ) do
                
                [first_urls|_] = tweet.entities.urls
                expanded_url = first_urls.expanded_url
                hackney = [follow_redirect: true]
                
                case HTTPoison.get(expanded_url, [], [ hackney: hackney ]) do
                        #prob paywalled
                        {:error, %HTTPoison.Error{reason: reason} } ->
                                IO.inspect reason
                                acc 
                        {:error, error } ->
                                IO.inspect error
                                acc
                        {:ok, http} ->
                                cond do
                                        #in case link goes to a pdf or something
                                        is_binary http.body ->
                                                acc
                                        true ->
                                                #extra clause - if no image return acc
                                                media_url = http.body |> Floki.find("meta[property='og:image']") |> Floki.attribute("content") |> List.first
                                                title = http.body |> Floki.find("meta[property='og:title']") |> Floki.attribute("content") |> List.first
                                                description = http.body |> Floki.find("meta[property='og:description']") |> Floki.attribute("content") |> List.first
                                
                                                cond do
                                                        media_url == nil or media_url == "" ->
                                                                acc
                                                        true ->                                                
                                                                [
                                                                        %Article{ media_url:      media_url, 
                                                                                text:           description,
                                                                                expanded_url:   expanded_url,
                                                                                title:          title,
                                                                                favorite_count: tweet.favorite_count,
                                                                                retweet_count:  tweet.retweet_count,
                                                                                followers_count: tweet.user.followers_count,
                                                                                tweet_id: tweet.id,
                                                                                tweet_id_str: 0,
                                                                                tweet_author: tweet.user.screen_name
                                                                                }
                                                                        | acc
                                                                ]
                                                end
                                end

                        _ ->
                                IO.puts "Something else happened"
                                acc
                                        
                end
        end
        
        defp get_media_tweet_info( %ExTwitter.Model.Tweet{}=tweet, acc ) do
                [ 
                        %Article{
                                media_url:      first_photo(tweet).media_url, 
                                text:           tweet.text,
                                expanded_url:   first_photo(tweet).expanded_url,
                                title:          "",
                                favorite_count: tweet.favorite_count,
                                retweet_count:  tweet.retweet_count,
                                followers_count: tweet.user.followers_count,
                                tweet_id:        0,
                                tweet_id_str: tweet.id_str,
                                tweet_author: tweet.user.screen_name
                                }
                        | acc
                ]
                
        end
        
               
        defp has_photos?( %ExTwitter.Model.Tweet{}=tweet ) do
                Map.has_key?(tweet.entities, :media) && Enum.any?(photos(tweet))
        end
        
        defp has_source_url?( %ExTwitter.Model.Tweet{}=tweet ) do
                Map.has_key?(tweet.entities, :urls) && Enum.any?(tweet.entities.urls) #&& Map.has_key?(tweet.entities.urls, :expanded_url)
        end
        
        defp photos(%ExTwitter.Model.Tweet{}=tweet) do
                tweet.entities.media
                        |> Enum.filter(
                                fn(medium) ->
                                        medium.type == "photo"
                                end )
                end
                
        defp first_photo(%ExTwitter.Model.Tweet{}=tweet) do
                photos(tweet)
                |> hd
                end
end

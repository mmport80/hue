defmodule Hue2.TweetInfo do
        alias Hue2.Repo
        alias Hue2.Article

        import Timex
        import Ecto.Query
        
        ##################################################################
        ##################################################################
        
        def get_articles() do
                Article 
                |> select([c,_], c ) 
                |> Hue2.Repo.all 
                |> less_than_a_day_old
                |> remove_dupes
                |> order
                |> Enum.take(100)
                #sort desc
                #more followers bad
                #more faves & rtwts good
        end
        
        defp order(articles) do
                articles
                |> Enum.sort_by(
                        fn(article) ->
                                 - (article.favorite_count + max(article.retweet_count - 1, 0) * 2.66) / article.followers_count
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
                                                        || (a.text == article.text)
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
        
        defp convert_ecto_to_timex(ecto_dt) do
                #to tuple
                {:ok, tuple_dt} = Ecto.DateTime.dump(ecto_dt)
                Timex.Date.from(tuple_dt)
        end
        
        ##################################################################
        ##################################################################
        
        #run every 15 mins
        #get and store article data
        
        
        #go thru each field
        #fill each depending on whether info is available
        #
        #ends with storing an article object
        
        def store() do
                ExTwitter.home_timeline([count: 200])
                        #filters relevant tweets
                        #creates augmented article objects
                        |> Enum.reduce(
                                [],
                                fn(tweet, acc) ->
                                        #use original quoted or retweeted tweet if a quote
                                        tweet = get_quoted_or_rtwd_status?(tweet)
                                        
                                        cond do 
                                                #reply to tweets lack context
                                                tweet.in_reply_to_status_id_str != nil ->
                                                        acc
                                                #does tweet redirect elsewhere?
                                                has_source_url?(tweet) ->
                                                        get_source_url_info(tweet, acc)
                                                #does tweet contain a photo?
                                                has_photos?(tweet) ->
                                                        get_media_tweet_info(tweet, acc )
                                                #just text tweet?
                                                true ->
                                                        get_text_tweet_info(tweet, acc)
                                                        #acc
                                        end
                                end                                                                      
                        )
                        |> order
                        #change to 10 for prod
                        |> Enum.take(100)
                        |> Enum.map(
                                fn(article) ->
                                        Repo.insert(article)
                                end 
                        )
                        
        end
        
        
        
        defp get_source_url_info( %ExTwitter.Model.Tweet{}=tweet, acc ) do
                
                [first_urls|_] = tweet.entities.urls
                expanded_url = first_urls.expanded_url
                hackney = [follow_redirect: true]
                
                cond do
                        #tmblr causes hackney to crash...
                        String.starts_with?(expanded_url, "http://tmblr.co/")
                        || String.starts_with?(expanded_url, "http://www.rug.nl/") 
                        || String.starts_with?(expanded_url, "http://abnormalreturns.com/")
                        || String.starts_with?(expanded_url, "http://on.rt.com")
                        || String.starts_with?(expanded_url, "http://dlvr.it")
                        || String.starts_with?(expanded_url, "http://stks.co")
                        -> 
                                acc
                        true ->
                                IO.puts "Current"
                                IO.puts expanded_url
                                IO.puts tweet.text
                                case HTTPoison.get(expanded_url, [], [ hackney: hackney ]) do
                                        #prob paywalled
                                        {:error, %HTTPoison.Error{reason: reason} } ->
                                                acc 
                                        {:error, error } ->
                                                acc
                                        {:ok, http} ->
                                                cond do
                                                        #in case link goes to a pdf or something
                                                        String.valid?(http.body) ->
                                                                #extra clause - if no image return acc
                                                                media_url = http.body |> Floki.find("meta[property='og:image']") |> Floki.attribute("content") |> List.first
                                                                title = http.body |> Floki.find("meta[property='og:title']") |> Floki.attribute("content") |> List.first
                                                                description = http.body |> Floki.find("meta[property='og:description']") |> Floki.attribute("content") |> List.first
                                                                
                                                                cond do
                                                                        media_url == nil or media_url == "" ->
                                                                        t = String.split(tweet.text, [" https://t.co"," http://t.co"]) |> List.first
                                                                        [
                                                                                %Article{ 
                                                                                        media_url:      "", 
                                                                                        text:           t,
                                                                                        expanded_url:   expanded_url,
                                                                                        title:          title,
                                                                                        favorite_count: get_favorite_count(tweet),
                                                                                        retweet_count:  tweet.retweet_count,
                                                                                        followers_count:        get_followers_count(tweet),
                                                                                        tweet_id:        0,
                                                                                        tweet_id_str: tweet.id_str,
                                                                                        tweet_author: tweet.user.screen_name
                                                                                        }
                                                                                | acc
                                                                        ]
                                                                        true ->   
                                                                                cond do
                                                                                        description != nil ->
                                                                                                a = String.length( description )
                                                                                        true ->
                                                                                                description = ""
                                                                                end                              
                                                                                [
                                                                                        %Article{ 
                                                                                                media_url:      media_url, 
                                                                                                text:           description,
                                                                                                expanded_url:   expanded_url,
                                                                                                title:          title,
                                                                                                favorite_count: get_favorite_count(tweet),
                                                                                                retweet_count:  tweet.retweet_count,
                                                                                                followers_count:        get_followers_count(tweet),
                                                                                                tweet_id:        0,
                                                                                                tweet_id_str: tweet.id_str,
                                                                                                tweet_author: tweet.user.screen_name
                                                                                                }
                                                                                        | acc
                                                                                ]
                                                                end
                                                        #PDF / PPT etc
                                                        true ->
                                                                t = String.split(tweet.text, [" https://t.co"," http://t.co"]) |> List.first
                                                                [
                                                                        %Article{ 
                                                                                media_url:      "", 
                                                                                text:           t,
                                                                                expanded_url:   expanded_url,
                                                                                title:          "",
                                                                                favorite_count: get_favorite_count(tweet),
                                                                                retweet_count:  tweet.retweet_count,
                                                                                followers_count:        get_followers_count(tweet),
                                                                                tweet_id:        0,
                                                                                tweet_id_str: tweet.id_str,
                                                                                tweet_author: tweet.user.screen_name
                                                                                }
                                                                        | acc
                                                                ]
                                                end

                                        _ ->
                                                IO.puts "Something else happened"
                                                acc
                                        
                               end
                end
        end
        
        defp get_media_tweet_info( %ExTwitter.Model.Tweet{}=tweet, acc ) do
                #break out t.co links at end of every tweet
                t = String.split(tweet.text, [" https://t.co"," http://t.co"]) |> List.first
                
                [ 
                        %Article{
                                media_url:              first_photo(tweet).media_url, 
                                text:                   t,
                                expanded_url:           first_photo(tweet).expanded_url,
                                title:                  "",
                                favorite_count:         get_favorite_count(tweet),
                                retweet_count:          tweet.retweet_count,
                                followers_count:        get_followers_count(tweet),
                                tweet_id:               0,
                                tweet_id_str:           tweet.id_str,
                                tweet_author:           tweet.user.screen_name
                                }
                        | acc
                ]
        end
        
        defp get_text_tweet_info( %ExTwitter.Model.Tweet{}=tweet, acc ) do
                #break out t.co links at end of every tweet
                t = String.split(tweet.text, [" https://t.co"," http://t.co"]) |> List.first
                
                [ 
                        %Article{
                                media_url:              "", 
                                text:                   t,
                                expanded_url:           "",
                                title:                  "",
                                favorite_count:         get_favorite_count(tweet),
                                retweet_count:          tweet.retweet_count,
                                followers_count:        get_followers_count(tweet),
                                tweet_id:               0,
                                tweet_id_str:           tweet.id_str,
                                tweet_author:           tweet.user.screen_name
                                }
                        | acc
                ]
        end
        
        
        #prob not necessary any more - recursively grabbing source tweet
        defp get_favorite_count(tweet) do
                cond do
                        tweet.retweeted_status == nil ->
                                tweet.favorite_count
                        true ->
                                tweet.retweeted_status.favorite_count
                end   
        end
        defp get_followers_count(tweet) do
                cond do
                        tweet.retweeted_status == nil ->
                                tweet.user.followers_count
                        true ->
                                tweet.retweeted_status.user.followers_count
                end   
        end
        
        
        #recursively grab quoted tweet until not more quoted tweets to be foun
        #instead of calling api, cast quoted status as a tweet struct directly?
        defp get_quoted_or_rtwd_status?(%ExTwitter.Model.Tweet{}=tweet) do
                cond do
                        tweet.retweeted_status == nil && tweet.quoted_status == nil ->
                                tweet
                        tweet.retweeted_status == nil ->
                                tweet.quoted_status.id |> ExTwitter.show |> get_quoted_or_rtwd_status?
                        true ->
                                tweet.retweeted_status.id |> ExTwitter.show |> get_quoted_or_rtwd_status?
                end
        end
        
        #photos but no video
        defp has_photos?( %ExTwitter.Model.Tweet{}=tweet ) do
                Map.has_key?(tweet.entities, :media) && Enum.any?(photos(tweet))
        end
        
        defp has_source_url?( %ExTwitter.Model.Tweet{}=tweet ) do
                Map.has_key?(tweet.entities, :urls)
                && Enum.any?(tweet.entities.urls)
                && (
                        url = tweet.entities.urls |> List.first
                        d_url = url.display_url
                        !String.match?(d_url,~r/vine.co/)
                        )
        end
        
        defp photos(%ExTwitter.Model.Tweet{}=tweet) do
                tweet.entities.media
                        |> Enum.filter(
                                fn(medium) ->
                                        medium.type == "photo" && !String.match?(medium.media_url,~r/ext_tw_video_thumb/)
                                end)
                end
                
        defp first_photo(%ExTwitter.Model.Tweet{}=tweet) do
                photos(tweet)
                |> hd
                end
end

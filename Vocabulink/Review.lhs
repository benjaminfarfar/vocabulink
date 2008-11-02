> module Vocabulink.Review where

> import Vocabulink.CGI
> import Vocabulink.DB
> import Vocabulink.Html
> import Vocabulink.Member
> import Vocabulink.Utils

> import Database.HDBC
> import Network.CGI
> import Text.XHtml.Strict
> import System.Time

> scheduleReview :: IConnection conn => conn -> Integer -> Integer -> IO ()
> scheduleReview c memberNo linkNo = do
>   quickInsert c "INSERT INTO link_to_review (member_no, link_no) \
>                 \VALUES (?, ?)" [toSql memberNo, toSql linkNo]
>     `catchSqlE` "You already have this link scheduled for review or there was an error."

> newReview :: String -> CGI CGIResult
> newReview link = do
>   c <- liftIO db
>   memberNo <- loginNumber
>   no <- liftIO $ intFromString link
>   case no of
>     Left  _ -> outputError 400 "Links are identified by numbers only." []
>     Right n -> do
>       liftIO $ scheduleReview c memberNo n
>       referer >>= redirect

Review the next link in the queue.

> reviewLink :: CGI CGIResult
> reviewLink = do
>   c <- liftIO db
>   memberNo <- loginNumber
>   linkNo <- liftIO $ query1 c "SELECT link_no FROM link_to_review \
>                               \WHERE member_no = ? AND target_time > current_timestamp \
>                               \ORDER BY target_time ASC LIMIT 1" [toSql memberNo]
>                        `catchSqlE` "Failed to retrieve next link for review."
>   case linkNo of
>     Nothing -> noLinksToReviewPage c memberNo
>     Just n  -> reviewLinkPage $ fromSql n

> reviewLinkPage :: Integer -> CGI CGIResult
> reviewLinkPage _ = output $ "blah"

> noLinksToReviewPage :: IConnection conn => conn -> Integer -> CGI CGIResult
> noLinksToReviewPage c memberNo = do
>   nextReview <- liftIO $ nextReviewTime c memberNo
>   let next = case nextReview of
>                Nothing   -> noHtml
>                Just diff -> paragraph <<
>                               ("Your next link for review is in " ++
>                                (timeDiffToString diff))
>   output $ renderHtml $ page t ["lexeme"]
>     [ h1 << t,
>       paragraph << "You don't have any links to review.",
>       next ]
>     where t = "No Links to Review"

> nextReviewTime :: IConnection conn => conn -> Integer -> IO (Maybe TimeDiff)
> nextReviewTime c memberNo = do
>   next <- query1 c "SELECT target_time - current_timestamp FROM link_to_review \
>                    \WHERE member_no = ? AND target_time > current_timestamp \
>                    \ORDER BY target_time ASC LIMIT 1" [toSql memberNo]
>             `catchSqlE` "Failed to determine next review time."
>   case next of
>     Nothing -> return Nothing
>     Just n  -> return $ Just (fromSql n)

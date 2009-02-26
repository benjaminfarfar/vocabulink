\section{Review}

Now that we know how to create links, its time to look at how to present them
to a member for review.

> module Vocabulink.Review (  newReview, linkReviewed, nextReview) where

For now, we have only 1 algorithm (SuperMemo 2).

> import qualified Vocabulink.Review.SM2 as SM2

> import Vocabulink.App
> import Vocabulink.CGI
> import Vocabulink.DB
> import Vocabulink.Html
> import Vocabulink.Link
> import Vocabulink.Utils

> import Control.Exception (throwDyn)

\subsection{Review Scheduling}

When a member indicates that they want to review a link, we just add it to the
@link_to_review@ table. This may change if we ever support multiple review
sets. The link review time is set to the current time by default so that it
immediately shows up for review (something we want no matter which algorithm
we're using).

We need to give the user feedback that they've successfully added the link to
their review set. For now, we redirect them back to the referrer because we
assume it will be the link page (which will then indicate in some way that
they're reviewing the link now). However, this is a good candidate for an
asynchronous call.

> newReview :: Integer -> Integer -> App CGIResult
> newReview memberNo linkNo = do
>   res <- quickStmt' "INSERT INTO link_to_review (member_no, link_no) \
>                     \VALUES (?, ?)" [toSql memberNo, toSql linkNo]
>   case res of
>     Nothing  -> error "Error scheduling link for review."
>     Just _   -> redirect =<< refererOrVocabulink

The client indicates a completed review with a @POST@ to @/review/linknumber/@
which will be dispatched to |linkReviewed|. Once we schedule the next review
time for the link, we move on to the next in their set.

> linkReviewed :: Integer -> Integer -> App CGIResult
> linkReviewed memberNo linkNo = do
>   recall      <- readRequiredInput "recall"
>   recallTime  <- readRequiredInput "recall-time"
>   res <- scheduleNextReview memberNo linkNo recall recallTime
>   case res of
>     Nothing  -> error "Failed to schedule next review."
>     Just _   -> redirect "/review/next"

We need to schedule the next review based on the review algorithm in use. The
algorithm needs to know how well the item was remembered. Also, we log the
amount of time it took to recall the item. The SM2 algorithm does not use this
information (nor any SuperMemo algorithm that I know of), but we may find it
useful when analyzing data later.

All database updates during this process are wrapped in a transaction.

@recall@ is passed as a real number between 0 and 1 to allow for future
variations in recall rating (such as fewer choices than 1 through 5 or less
discrete options like a slider).

@previous@ is passed as well. This is the actual time in seconds between this
and the last review (not the scheduled time difference).

> scheduleNextReview :: Integer -> Integer -> Double -> Integer -> App (Maybe ())
> scheduleNextReview memberNo linkNo recall recallTime = do
>   previous <- previousInterval memberNo linkNo
>   case previous of
>     Nothing  -> return Nothing
>     Just p   -> withTransaction' $ do
>       seconds <- SM2.reviewInterval memberNo linkNo p recall
>       case seconds of
>         Nothing  -> throwDyn ()
>         Just s   -> do
>           run'  "INSERT INTO link_review (member_no, link_no, recall, \
>                                          \recall_time, target_time) \
>                 \VALUES (?, ?, ?, ?, \
>                        \(SELECT target_time FROM link_to_review \
>                 \WHERE member_no = ? AND link_no = ?))"
>                 [  toSql memberNo, toSql linkNo, toSql recall,
>                    toSql recallTime, toSql memberNo, toSql linkNo]
>           run' ("UPDATE link_to_review \
>                 \SET target_time = current_timestamp + interval \
>                 \'" ++ (show s) ++ " seconds" ++ "' \
>                 \WHERE member_no = ? AND link_no = ?")
>                [toSql memberNo, toSql linkNo]
>           return ()

\subsection{Review Pages}

Here's the entry point for the client to request reviews. It's pretty simple:
we just request the next link from @link_to_review@ by @target_time@. If
there's none, we send the client to a ``congratulations'' page. If there is a
link for review, we send them to the review page.

> nextReview :: Integer -> App CGIResult
> nextReview memberNo = do
>   linkNo <- queryTuples'
>     "SELECT link_no FROM link_to_review \
>     \WHERE member_no = ? AND current_timestamp >= target_time \
>     \ORDER BY target_time ASC LIMIT 1" [toSql memberNo]
>   case linkNo of
>     Just []     -> noLinksToReviewPage
>     Just [[n]]  -> reviewLinkPage $ fromSql n
>     _           -> error "Failed to retrieve next link for review."

The review page is pretty basic. It displays a link with the destination
covered up by a question mark. Once the member clicks the question mark (to
find out what is hidden beneath it) it reveals the lexeme, records the total
amount of recall time taken, and displays a recall feedback form (currently a
row of 5 buttons for working with the SM2 algorithm). Once the member clicks a
recall number, it sends the information off to |linkReviewed| to record the
details and schedule the next review. This sends the client to |nextReview|
which begins the process all over again.

> reviewLinkPage :: Integer -> App CGIResult
> reviewLinkPage linkNo = do
>   l <- getLink linkNo
>   case l of
>     Nothing  -> simplePage "Error: Unable to retrieve link." [CSS "link"] []
>     Just l'  -> do
>       let source  = encodeString $ linkOrigin l'
>           dest    = encodeString $ linkDestination l'
>       stdPage ("Review: " ++ source ++ " -> ?")
>               [CSS "link", JS "MochiKit", JS "review"] []
>         [  thediv ! [identifier "baseline", theclass "link"] <<
>              linkHtml (stringToHtml source)
>                (anchor ! [identifier "lexeme-cover", href "#"] << "?"),
>            form ! [action ("/review/" ++ (show linkNo)), method "POST"] <<
>              [  hidden "recall-time" "",
>                 hidden "hidden-lexeme" dest,
>                 fieldset ! [identifier "recall-buttons", thestyle "display: none"] <<
>                   map (recallButton 5) [0..5] ] ]

This creates a ``recall button''. It returns a button with a decimal recall
value based on an integral button number. It hopefully allows us to make the
recall options more flexible in the future.

You may get unpleasant results when passing totals and is that don't cleanly
divide.

> recallButton :: Integer -> Integer -> Html
> recallButton total i = let q :: Double = (fromIntegral i) / (fromIntegral total) in
>                        button ! [name "recall", value (show q)] << show i

The member has no more links to review for now, let's display a page letting
them know that.

Here's a critical chance to:

\begin{itemize}
\item Give positive feedback to encourage the behavior of getting through the
      review stack.
\item Point the member to other places of interest on the site.
\end{itemize}

> noLinksToReviewPage :: App CGIResult
> noLinksToReviewPage = do
>   simplePage "No Links to Review" [CSS "link"]
>     [ paragraph << "Take a break! \
>                    \You don't have any links to review right now." ]

In order to determine the next review interval, the review scheduling algorithm
may need to know how long the last review period was (in fact, any algorithm
based on spaced reptition will). This returns the actual, not scheduled, amount
of time between the current and last review in seconds.

Note that this will not work before the link has been reviewed. We expect that
the review algorithm does not have to be used for determining the first review
(immediate).

> previousInterval :: Integer -> Integer -> App (Maybe Integer)
> previousInterval memberNo linkNo = do
>   v <- queryValue'  "SELECT extract(epoch from current_timestamp - \
>                                    \(SELECT actual_time FROM link_review \
>                                     \WHERE member_no = ? AND link_no = ? \
>                                     \ORDER BY actual_time DESC LIMIT 1))"
>                     [toSql memberNo, toSql linkNo]
>   return $ fmap fromSql v

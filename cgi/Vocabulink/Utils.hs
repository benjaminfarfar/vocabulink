-- Copyright 2008, 2009, 2010, 2011, 2012 Chris Forno

-- This file is part of Vocabulink.

-- Vocabulink is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Affero General Public License as published by the Free
-- Software Foundation, either version 3 of the License, or (at your option)
-- any later version.

-- Vocabulink is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE. See the GNU Affero General Public License
-- for more details.

-- You should have received a copy of the GNU Affero General Public License
-- along with Vocabulink. If not, see <http://www.gnu.org/licenses/>.

-- Utility Functions

-- Here are some functions that aren't specific to Vocabulink, but that don't
-- exist in any libraries I know of. We also use this module to export some
-- oft-used functions for other modules.

module Vocabulink.Utils ( (?), (<$$>)
                        , safeHead, safeTail, every2nd, every3rd
                        , partitionHalves, partitionThirds
                        , translate, trim, convertLineEndings
                        , currentDay, currentYear, diffTimeToSeconds, epochUTC, utcEpoch
                        , basename, isFileReadable, sendMail
                        , logError, prettyPrint
                        , matchRegexAllText
                        {- Codec.Binary.UTF8.String -}
                        , encodeString, decodeString
                        {- Control.Applicative -}
                        , pure, (<$>), (<*>)
                        {- Control.Applicative.Error -}
                        , maybeRead
                        {- Control.Arrow -}
                        , first, second, (***)
                        {- Control.Monad -}
                        , liftM, Control.Monad.join, msum, when, unless, replicateM, mzero, forM, forM_
                        {- Control.Monad.Trans -}
                        , liftIO, MonadIO
                        {- Data.Bool.HT -}
                        , if'
                        {- Data.Char -}
                        , toLower
                        {- Data.ByteString.Lazy -}
                        , readFile, writeFile
                        {- Data.Either.Utils -}
                        , forceEither
                        {- Data.List -}
                        , intercalate, (\\), nub
                        {- Data.List.Split -}
                        , splitOn, splitEvery
                        {- Data.Maybe -}
                        , maybe, fromMaybe, fromJust, isJust, isNothing, mapMaybe, catMaybes
                        {- Data.Monoid -}
                        , mempty, mappend, mconcat
                        {- Database.TemplatePG -}
                        , withTransaction, rollback, execute, queryTuple, queryTuples, insertIgnore
                        {- Data.Time.Calendar -}
                        , Day, addDays, diffDays, showGregorian
                        {- Data.Time.Clock -}
                        , UTCTime, DiffTime, getCurrentTime, diffUTCTime, secondsToDiffTime
                        {- Data.Time.Clock.POSIX -}
                        , posixSecondsToUTCTime, utcTimeToPOSIXSeconds
                        {- Data.Time.Format -}
                        , formatTime, readTime
                        {- Debug.Trace -}
                        , trace
                        {- Data.Tuple.Curry -}
                        , uncurryN
                        {- System.FilePath -}
                        , (</>), (<.>), takeExtension, replaceExtension, takeBaseName, takeFileName
                        {- System.IO -}
                        , Handle
                        {- System.Locale -}
                        , defaultTimeLocale
                        {- System.Posix.Time -}
                        , epochTime
                        {- System.Posix.Types -}
                        , EpochTime
                        {- Text.Regex -}
                        , subRegex, mkRegex
                        ) where

import Codec.Binary.UTF8.String (encodeString, decodeString)
import Control.Applicative (pure, (<$>), (<*>))
import Control.Applicative.Error (maybeRead)
import Control.Arrow (first, second, (***))
import Control.Monad
import Control.Monad.Trans (liftIO, MonadIO)
import Data.ByteString.Lazy (readFile, writeFile)
import Data.Char (toLower, isSpace)
import Data.Either.Utils (forceEither) -- MissingH
import Data.List (intercalate, (\\), nub)
import Data.List.Split (splitOn, splitEvery)
import Data.List.Utils as LU -- MissingH
import Data.Maybe (fromMaybe, fromJust, isJust, isNothing, mapMaybe, catMaybes)
import Data.Monoid
import Database.TemplatePG
import Debug.Trace (trace)
import Data.Bool.HT (if')
-- Time is notoriously difficult to deal with in Haskell. It gets especially
-- tricky when working with the database and libraries that expect different
-- formats.
import Data.Time.Calendar (Day, toGregorian, showGregorian, addDays, diffDays)
import Data.Time.Clock (UTCTime, DiffTime, getCurrentTime, diffUTCTime, secondsToDiffTime)
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import Data.Time.Format (formatTime, readTime)
import Data.Time.LocalTime (getCurrentTimeZone, utcToLocalTime, LocalTime(..))
import Data.Tuple.Curry (uncurryN)
import System.Directory (getPermissions, doesFileExist, readable)
import System.Exit (ExitCode(..))
import System.FilePath ( (</>), (<.>), takeExtension, replaceExtension
                       , takeBaseName, takeFileName )
import System.IO (Handle, hPutStr, hPutStrLn, hClose, stderr)
import System.Locale (defaultTimeLocale)
import System.Posix.Time (epochTime)
import System.Posix.Types (EpochTime)
import System.Process (createProcess, waitForProcess, proc, std_in, StdStream(..))
import Text.Regex (Regex, subRegex, mkRegex, matchRegexAll)

import Prelude hiding (readFile, writeFile)

-- It's often useful to have the compactness of the traditional tertiary
-- operator rather than an if then else. The |(?)| operator can be used like:

-- Bool ? trueExpression $ falseExpression

-- I think I originally saw this defined on the Haskell wiki.

infixl 1 ?
(?) :: Bool -> a -> a -> a
(?) = if'

-- Often it's handy to be able to lift an operation into 2 monads with little
-- verbosity. Parsec may have claimed this operator name before me, but |<$$>|
-- just makes too much sense as 2 |<$>|s.

(<$$>) :: (Monad m1, Monad m) => (a -> r) -> m (m1 a) -> m (m1 r)
(<$$>) = liftM . liftM

-- Lists

-- In case we want don't want our program to crash when taking the head of the
-- empty list, we need to provide a default:

safeHead :: a -> [a] -> a
safeHead d []     = d
safeHead _ (x:_)  = x

safeTail :: [a] -> [a]
safeTail []     = []
safeTail (_:xs) = xs

-- If we want to layout items from left to right in HTML columns, we need to
-- break 1 list down into smaller lists. |everyNth| is not a great name, but
-- |cycleN| is equally confusing. These use a neat |foldr| trick I found on the
-- Haskell wiki.

-- every2nd [1,2,3] =>
-- 3 ([],[]) => ([3],[])
-- 2 ([3],[]) => ([2],[3])
-- 1 ([2],[3]) => ([1,3],[2])

every2nd :: [a] -> ([a], [a])
every2nd = foldr (\a ~(x,y) -> (a:y,x)) ([],[])

-- every3rd [1,2,3,4,5] =>
-- 5 ([],[],[]) => ([5],[],[])
-- 4 ([5],[],[]) => ([4],[5],[])
-- 3 ([4],[5],[]) => ([3],[4],[5])
-- 2 ([3],[4],[5]) => ([2,5],[3],[4])
-- 1 ([2,5],[3],[4]) => ([1,4],[2,5],[3])

every3rd :: [a] -> ([a], [a], [a])
every3rd = foldr (\a ~(x,y,z) -> (a:z,x,y)) ([],[],[])

partitionHalves :: [a] -> ([a], [a])
partitionHalves x = (take len x, drop len x)
 where len = ceiling $ fromIntegral (length x) / 2

partitionThirds :: [a] -> ([a], [a], [a])
partitionThirds x = (take len x, take len (drop len x), drop (len * 2) x)
 where len = ceiling $ fromIntegral (length x) / 3

-- This is like the Unix tr utility. It takes a list of search/replacements and
-- then performs them on the list.

translate :: (Eq a) => [(a, a)] -> [a] -> [a]
translate sr = map (\s -> fromMaybe s $ lookup s sr)

-- | Trim whitespace from the beginning and end of a string.
-- from https://secure.wikimedia.org/wikipedia/en/wiki/Trim_(programming)#Haskell
trim :: String -> String
trim = f . f
 where f = reverse . dropWhile isSpace

-- We might get data from various sources that use different end-of-line
-- terminators. But we want to always work with just newlines.

-- We use |join| instead of |unlines| because |unlines| adds a trailing newline.

convertLineEndings :: String -> String
convertLineEndings = LU.join "\n" . splitLines

-- This comes from Real World Haskell.

splitLines :: String -> [String]
splitLines [] = []
splitLines cs =
  let (pre, suf) = break isLineTerminator cs in
  pre : case suf of
          ('\r':'\n':rest) -> splitLines rest
          ('\r':rest)      -> splitLines rest
          ('\n':rest)      -> splitLines rest
          _                -> []

isLineTerminator :: Char -> Bool
isLineTerminator = (`elem` "\r\n")

-- Time

currentDay :: IO Day
currentDay = getCurrentTime >>= serverDay

-- | Get the current year as a 4-digit number.
currentYear :: IO Integer
currentYear = do
  (year, _, _) <- serverDate =<< getCurrentTime
  return year

serverDay :: UTCTime -> IO Day
serverDay utc = do
  tz <- getCurrentTimeZone
  let (LocalTime day _) = utcToLocalTime tz utc
  return day

serverDate :: UTCTime -> IO (Integer, Int, Int)
serverDate utc = toGregorian <$> serverDay utc

diffTimeToSeconds :: DiffTime -> Integer
diffTimeToSeconds = floor . toRational

epochUTC :: UTCTime -> Integer
epochUTC = floor . realToFrac . utcTimeToPOSIXSeconds

utcEpoch :: Integer -> UTCTime
utcEpoch = posixSecondsToUTCTime . fromIntegral

-- For files we receive via HTTP, we can't make assumptions about the path
-- separator.

basename :: FilePath -> FilePath
basename = reverse . takeWhile (`notElem` "/\\") . reverse

isFileReadable :: FilePath -> IO Bool
isFileReadable f = do
  exists' <- doesFileExist f
  if exists'
    then readable <$> getPermissions f
    else return False

sendMail :: String -> String -> String -> String -> IO (Maybe ())
sendMail from address subject body = do
  (Just inF, _, _, pr) <- createProcess (proc "mail"
                                              ["-r", from
                                              ,"-s", subject
                                              ,address])
                                        {std_in = CreatePipe}
  hPutStr inF body >> hClose inF
  status <- waitForProcess pr
  case status of
    ExitFailure _ -> return Nothing
    ExitSuccess   -> return $ Just ()

-- Log a message to standard error. It'll get picked up by svlogd.

logError :: String -> String -> IO ()
logError typ msg = hPutStrLn stderr $ "[" ++ typ ++ "] " ++ msg

class PrettyPrint a where
  prettyPrint :: a -> String

-- > instance (Integral a) => PrettyPrint a where

instance PrettyPrint Integer where
  prettyPrint = reverse . intercalate "," . splitEvery 3 . reverse . show

-- TODO: instance PrettyPrint Float

instance PrettyPrint Day where
  prettyPrint = formatTime defaultTimeLocale "%F"

instance PrettyPrint UTCTime where
  prettyPrint = formatTime defaultTimeLocale "%F %R"

matchRegexAllText :: Regex -> String -> [(String, [String])]
matchRegexAllText rx s =
  case matchRegexAll rx s of
    Just (_, match, rest, subs) -> (match, subs) : matchRegexAllText rx rest
    Nothing -> []

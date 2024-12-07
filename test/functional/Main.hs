module Main (main) where

import Data.Word (Word8)
import Functional.Prelude
import Running.Driver (runAppWith)
import System.Environment (withArgs)
import Test.Tasty (defaultMain)

main :: IO ()
main =
  defaultMain
    $ testGroup
      "Functional"
      [ testConvertToDistance,
        testConvertToDuration,
        testConvertToPace
      ]

testConvertToDistance :: TestTree
testConvertToDistance = testCase "Converts to Distance" $ do
  runArgs mkArgs vals
  where
    mkArgs d p = ["convert", "--duration", d, "--pace", p]
    vals =
      zip
        [1 ..]
        [ ("3h", "4m30s /km", "40.0 km"),
          ("20m", "4m /kilometer", "5.0 km"),
          ("2h30m", "5m /mi", "30.0 mi"),
          ("3h", "5m /mile", "36.0 mi")
        ]

testConvertToDuration :: TestTree
testConvertToDuration = testCase "Converts to Duration" $ do
  runArgs mkArgs vals
  where
    mkArgs d p = ["convert", "--distance", d, "--pace", p]
    vals =
      zip
        [1 ..]
        [ ("42 km", "4m30s", "3h 9'00\""),
          ("42 kilometers", "4m30s /km", "3h 9'00\""),
          ("42 km", "4m30s /mi", "1h 57'28\""),
          ("10 mi", "4m30s", "45'00\""),
          ("10 miles", "4m30s /km", "1h 12'24\""),
          ("10 mi", "4m30s /mi", "45'00\""),
          ("marathon", "5m", "3h 30'58\""),
          ("marathon", "5m /km", "3h 30'58\""),
          ("marathon", "5m /mi", "2h 11'07\""),
          ("half-marathon", "5m", "1h 45'29\""),
          ("half-marathon", "5m /km", "1h 45'29\""),
          ("half-marathon", "5m /mi", "1h 5'34\"")
        ]

testConvertToPace :: TestTree
testConvertToPace = testCase "Converts to Pace" $ do
  runArgs mkArgs vals
  where
    mkArgs d p = ["convert", "--distance", d, "--duration", p]
    vals =
      zip
        [1 ..]
        [ ("42 m", "3h30s", "71h 37'37\" /km"),
          ("42 km", "3h30s", "4'18\" /km"),
          ("42 mi", "3h30s", "4'18\" /mi"),
          ("10 meters", "4h", "400h 0'00\" /km"),
          ("10 kilometers", "4h", "24'00\" /km"),
          ("10 miles", "4h", "24'00\" /mi"),
          ("marathon", "4h20s", "5'42\" /km"),
          ("half-marathon", "3h30s", "8'33\" /km")
        ]

runArgs :: (a -> b -> List String) -> List (Word8, (a, b, Text)) -> IO ()
runArgs mkArgs vals =
  for_ vals $ \(idx, (d, p, e)) -> do
    let args = mkArgs d p

    r <- withArgs args $ runAppWith pure

    let msg =
          mconcat
            [ showt @Word8 idx,
              ". Args: ",
              showt args,
              "\n   Diff: ",
              e,
              " /= ",
              r
            ]
    assertBool (unpackText msg) (e == r)

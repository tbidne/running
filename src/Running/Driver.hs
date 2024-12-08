module Running.Driver
  ( -- * Main
    runApp,
    runAppWith,
  )
where

import Options.Applicative qualified as OA
import Running qualified
import Running.Config.Args (Args (command), parserInfo)
import Running.Config.Args.Command
  ( Command (Convert, Scale),
    ConvertFinal (ConvertDistance, ConvertDuration, ConvertPace),
    DistanceDurationPaceArgs,
    ScaleFinal (ScaleDistance, ScaleDuration, ScalePace),
    argsToConvert,
    argsToScale,
  )
import Running.Data.Distance (SomeDistance (MkSomeDistance))
import Running.Data.Distance qualified as Dist
import Running.Data.Distance.Units
  ( DistanceUnit (Kilometer),
    SDistanceUnit (SKilometer, SMeter, SMile),
  )
import Running.Data.Pace (Pace (MkPace))
import Running.Prelude

runApp :: IO ()
runApp = runAppWith (putStrLn . unpackText)

runAppWith :: (Text -> IO a) -> IO a
runAppWith handler = do
  args <- OA.execParser parserInfo
  case args.command of
    Convert ddpArgs -> handleConvert handler ddpArgs
    Scale ddpArgs scaleFactor -> handleScale handler ddpArgs scaleFactor

handleConvert :: (Text -> IO a) -> DistanceDurationPaceArgs -> IO a
handleConvert handler ddpArgs =
  argsToConvert ddpArgs >>= \case
    ConvertDistance duration pace -> do
      let dist = Running.calculateSomeDistance duration pace
      handler $ display dist
    ConvertDuration paceOptUnits dist -> do
      let duration = case paceOptUnits of
            Left pace -> Running.calculateSomeDuration dist pace
            Right paceDuration -> case dist of
              MkSomeDistance sdist distx ->
                case sdist of
                  SMeter ->
                    let disty = Dist.convertDistance distx
                     in Running.calculateDuration disty (MkPace @Kilometer paceDuration)
                  SKilometer -> Running.calculateDuration distx (MkPace paceDuration)
                  SMile -> Running.calculateDuration distx (MkPace paceDuration)
      handler $ display duration
    ConvertPace duration dist -> do
      let pace = Running.calculateSomePace dist duration
      handler $ display pace

handleScale :: forall a. (Text -> IO a) -> DistanceDurationPaceArgs -> PDouble -> IO a
handleScale handler ddpArgs scaleFactor =
  argsToScale ddpArgs >>= \case
    ScaleDistance dist -> scaleDisplay dist
    ScaleDuration duration -> scaleDisplay duration
    ScalePace paceOptUnits -> case paceOptUnits of
      Left pace -> scaleDisplay pace
      Right duration -> scaleDisplay duration
  where
    scaleDisplay :: forall b. (Display b, MSemiSpace b PDouble) => b -> IO a
    scaleDisplay = handler . display . (.* scaleFactor)

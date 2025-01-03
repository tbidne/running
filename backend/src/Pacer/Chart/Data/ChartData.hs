module Pacer.Chart.Data.ChartData
  ( ChartData (..),
    ChartY (..),
    ChartY1 (..),
    mkChartData,
    mkChartDatas,
  )
where

import Data.Aeson (KeyValue ((.=)), ToJSON (toJSON), Value)
import Data.Aeson qualified as Asn
import Data.List (all)
import Data.List qualified as L
import Data.Sequence (Seq (Empty))
import Data.Sequence.NonEmpty qualified as NESeq
import Pacer.Chart.Data.ChartRequest
  ( ChartRequest (filters, title, y1Axis, yAxis),
    ChartRequests (unChartRequests),
    FilterExpr,
    FilterOp (MkFilterOp),
    FilterType (FilterDistance, FilterDuration, FilterLabel, FilterPace),
    YAxisType
      ( YAxisDistance,
        YAxisDuration,
        YAxisPace
      ),
    eval,
  )
import Pacer.Chart.Data.Run
  ( Run (datetime, distance, duration),
    RunTimestamp,
    SomeRun (MkSomeRun),
    SomeRuns (MkSomeRuns),
    SomeRunsKey (MkSomeRunsKey, unSomeRunsKey),
  )
import Pacer.Chart.Data.Run qualified as Run
import Pacer.Data.Distance (Distance (unDistance), SomeDistance)
import Pacer.Data.Distance.Units
  ( DistanceUnit (Kilometer, Meter, Mile),
  )
import Pacer.Data.Distance.Units qualified as DistU
import Pacer.Data.Duration (Duration (unDuration), Seconds)
import Pacer.Data.Pace (SomePace (MkSomePace))
import Pacer.Exception (CreateChartE (CreateChartFilterEmpty))
import Pacer.Prelude

-- | Holds chart data.
data ChartData
  = ChartDataY ChartY
  | ChartDataY1 ChartY1
  deriving stock (Eq, Show)

instance ToJSON ChartData where
  toJSON (ChartDataY x) = toJSON x
  toJSON (ChartDataY1 x) = toJSON x

-- | Data for a chart with a single Y axis.
data ChartY = MkChartY
  { -- | X and Y axis data.
    values :: NESeq (Tuple2 RunTimestamp Double),
    -- | Y axis type. This is used for the label on the line itself, __not__
    -- the y-axis (that label is on ChartOptions).
    yType :: YAxisType
  }
  deriving stock (Eq, Show)

instance ToJSON ChartY where
  toJSON c =
    Asn.object
      [ "xAxis" .= x,
        "yAxes" .= [yAxis]
      ]
    where
      (x, y) = L.unzip $ toList c.values

      yAxis = mkYJson y c.yType "y"

-- | Data for a chart with two Y axes.
data ChartY1 = MkChartY1
  { -- | Data for a chart with two y Axes.
    values :: NESeq (Tuple3 RunTimestamp Double Double),
    -- | Type of first Y axis.
    yType :: YAxisType,
    -- | Type of second Y axis.
    y1Type :: YAxisType
  }
  deriving stock (Eq, Show)

instance ToJSON ChartY1 where
  toJSON c =
    Asn.object
      [ "xAxis" .= x,
        "yAxes" .= [yAxis, y1Axis]
      ]
    where
      (x, y, y1) = L.unzip3 $ toList c.values
      yAxis = mkYJson y c.yType "y"
      y1Axis = mkYJson y1 c.y1Type "y1"

mkYJson :: [Double] -> YAxisType -> Text -> Value
mkYJson yVal yType yId =
  Asn.object
    [ "data" .= yVal,
      "label" .= yType,
      "fill" .= False,
      "pointHoverRadius" .= i 20, -- point size on hover
      "tension" .= i 0,
      "yAxisID" .= yId
    ]

-- | Accumulator for chart with a single Y axis.
type AccY = NESeq (Tuple2 RunTimestamp Double)

-- | Accumulator for chart with two Y axes.
type AccY1 = NESeq (Tuple3 RunTimestamp Double Double)

-- | Turns a sequence of runs and chart requests into charts.
mkChartDatas ::
  ( FromInteger a,
    MetricSpace a,
    Ord a,
    Semifield a,
    Show a,
    ToReal a
  ) =>
  -- | Final distance unit to use.
  DistanceUnit ->
  SomeRuns a ->
  ChartRequests a ->
  Either CreateChartE (Seq ChartData)
mkChartDatas finalDistUnit runs =
  traverse (mkChartData finalDistUnit runs) . (.unChartRequests)

-- NOTE: HLint incorrectly thinks some brackets are unnecessary.
-- See NOTE: [Brackets with OverloadedRecordDot].
--
{- HLINT ignore "Redundant bracket" -}

-- | Turns a sequence of runs and a chart request into a chart.
mkChartData ::
  forall a.
  ( FromInteger a,
    MetricSpace a,
    Ord a,
    Semifield a,
    Show a,
    ToReal a
  ) =>
  -- | Final distance unit to use.
  DistanceUnit ->
  -- | List of runs.
  SomeRuns a ->
  -- | Chart request.
  ChartRequest a ->
  -- | ChartData result. Nothing if no runs passed the request's filter.
  Either CreateChartE ChartData
mkChartData
  finalDistUnit
  (MkSomeRuns (SetToSeqNE someRuns@(MkSomeRunsKey (MkSomeRun sd _) :<|| _)))
  request =
    case filteredRuns of
      Empty -> Left $ CreateChartFilterEmpty request.title
      r :<| rs -> Right (mkChartDataSets (r :<|| rs))
    where
      filteredRuns = filterRuns someRuns request.filters

      mkChartDataSets :: NESeq (SomeRun a) -> ChartData
      mkChartDataSets runs = case request.y1Axis of
        Nothing ->
          let vals = withSingI sd $ foldMap1 toAccY runs
              yType = request.yAxis
           in ChartDataY (MkChartY vals yType)
        Just y1Type ->
          let vals = withSingI sd $ foldMap1 (toAccY1 y1Type) runs
              yType = request.yAxis
           in ChartDataY1 (MkChartY1 vals yType y1Type)

      toAccY :: SomeRun a -> AccY
      toAccY sr@(MkSomeRun _ r) = NESeq.singleton (r.datetime, toY sr)

      toAccY1 :: YAxisType -> SomeRun a -> AccY1
      toAccY1 yAxisType sr@(MkSomeRun _ r) =
        NESeq.singleton (r.datetime, toY sr, toYHelper yAxisType sr)

      toY :: SomeRun a -> Double
      toY = toYHelper request.yAxis

      toYHelper :: YAxisType -> SomeRun a -> Double
      toYHelper axisType (MkSomeRun s r) = case axisType of
        YAxisDistance ->
          withSingI s $ toℝ $ case finalDistUnit of
            -- NOTE: [Brackets with OverloadedRecordDot]
            Meter -> (DistU.convertToKilometers_ r).distance.unDistance
            Kilometer -> (DistU.convertToKilometers_ r).distance.unDistance
            Mile -> (DistU.convertDistance_ @_ @Mile r).distance.unDistance
        YAxisDuration -> toℝ r.duration.unDuration
        YAxisPace ->
          withSingI s $ toℝ $ case finalDistUnit of
            Meter -> runToPace (DistU.convertToKilometers_ r)
            Kilometer -> runToPace (DistU.convertToKilometers_ r)
            -- TODO: Previously this was converting to Kilometers, but that
            -- was almost certainly a bug that tests did not catch.
            -- Let's write one.
            Mile -> runToPace (DistU.convertDistance_ @_ @Mile r)
          where
            runToPace runUnits =
              (Run.derivePace runUnits).unPace.unDuration

filterRuns ::
  forall a.
  ( FromInteger a,
    MetricSpace a,
    Ord a,
    Semifield a,
    Show a
  ) =>
  NESeq (SomeRunsKey a) ->
  List (FilterExpr a) ->
  Seq (SomeRun a)
filterRuns rs filters = (.unSomeRunsKey) <$> NESeq.filter filterRun rs
  where
    filterRun :: SomeRunsKey a -> Bool
    filterRun r = all (eval (applyFilter r)) filters

    applyFilter :: SomeRunsKey a -> FilterType a -> Bool
    applyFilter srk (FilterLabel lbl) = applyLabel srk.unSomeRunsKey lbl
    applyFilter srk (FilterDistance op d) = applyDist srk.unSomeRunsKey op d
    applyFilter srk (FilterDuration op d) = applyDur srk.unSomeRunsKey op d
    applyFilter srk (FilterPace op p) = applyPace srk.unSomeRunsKey op p

    applyLabel :: SomeRun a -> Text -> Bool
    applyLabel (MkSomeRun _ r) lbl = lbl `elem` r.labels

    applyDist :: SomeRun a -> FilterOp -> SomeDistance (Positive a) -> Bool
    applyDist (MkSomeRun @runDist sr r) op fDist =
      withSingI sr $ (opToFun op) r.distance fDist'
      where
        fDist' :: Distance runDist (Positive a)
        fDist' = withSingI sr $ DistU.convertDistance_ @_ @runDist fDist

    applyDur :: SomeRun a -> FilterOp -> Seconds (Positive a) -> Bool
    applyDur (MkSomeRun _ r) op = (opToFun op) r.duration

    applyPace :: SomeRun a -> FilterOp -> SomePace (Positive a) -> Bool
    applyPace someRun@(MkSomeRun _ _) op (MkSomePace sfp fPace) =
      -- 1. convert someRun to runPace
      case Run.deriveSomePace someRun of
        (MkSomePace @runDist srp runPace) ->
          -- 2. convert filterPace to runPace's units
          withSingI srp
            $ withSingI sfp
            $ case DistU.convertDistance_ @_ @runDist fPace of
              fPace' -> (opToFun op) runPace ((.unPositive) <$> fPace')

    opToFun :: forall b. (Ord b) => FilterOp -> (b -> b -> Bool)
    opToFun (MkFilterOp _ f) = f

i :: Int -> Int
i = id

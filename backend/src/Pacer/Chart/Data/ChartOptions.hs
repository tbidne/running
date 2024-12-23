module Pacer.Chart.Data.ChartOptions
  ( ChartOptions (..),
    mkChartOptions,
  )
where

import Data.Aeson (KeyValue ((.=)), ToJSON (toJSON))
import Data.Aeson qualified as Asn
import Pacer.Chart.Data.ChartRequest
  ( ChartRequest (title, y1Axis, yAxis),
    YAxisType
      ( YAxisDistance,
        YAxisDuration,
        YAxisPace
      ),
  )
import Pacer.Data.Distance (DistanceUnit)
import Pacer.Prelude

-- | Possible y-axis positions.
data YPosition
  = YLeft
  | YRight
  deriving stock (Eq, Show)

instance ToJSON YPosition where
  toJSON YLeft = "left"
  toJSON YRight = "right"

-- | Y-axis options.
data YOptions = MkYOptions
  { -- | Label that appears on the (vertical) y-axis itself.
    label :: Text,
    -- | Y-axis position.
    position :: YPosition
  }
  deriving stock (Eq, Show)

instance ToJSON YOptions where
  toJSON y =
    Asn.object
      [ -- "min" .= (0 :: Int),
        "position" .= y.position,
        "title"
          .= Asn.object
            [ "display" .= True,
              "text" .= y.label
            ]
      ]

-- | Chart option data.
data ChartOptions = MkChartOptions
  { -- | Overall chart title.
    title :: Text,
    -- | Y-axis options.
    yOptions :: YOptions,
    -- | Possible y1-axis options.
    y1Options :: Maybe YOptions
  }
  deriving stock (Eq, Show)

instance ToJSON ChartOptions where
  toJSON c =
    Asn.object
      [ "plugins"
          .= Asn.object
            [ "title"
                .= Asn.object
                  [ "display" .= True,
                    "text" .= c.title
                  ]
            ],
        "responsive" .= True,
        "maintainAspectRatio" .= False,
        "scales" .= scales
      ]
    where
      scales =
        Asn.object
          $ [ "x"
                .= Asn.object
                  [ "time"
                      .= Asn.object
                        [ "displayFormats"
                            .= Asn.object
                              [ -- NOTE: Keeping the lablel relatively concise as it
                                -- is more readable, and the tooltip contains the full
                                -- timestamp anyway.
                                "day" .= t "dd MMM yy"
                              ],
                          "unit" .= t "day"
                        ],
                    "title"
                      .= Asn.object
                        [ "display" .= True,
                          "text" .= t "datetime"
                        ],
                    -- NOTE: timeseries over cartesian (string "time") as the
                    -- spaces out events equally, while the latter spaces
                    -- relative to the actual time difference. But this is
                    -- usually quite silly as e.g. official marathons may be
                    -- very spaces out, and this provides no actual value.
                    "type" .= t "timeseries"
                  ],
              "y" .= c.yOptions
            ]
          ++ maybe [] (\z -> ["y1" .= z]) c.y1Options

-- | Creates a chart options from the request. The distance unit is used
-- for labeling the axis.
mkChartOptions :: DistanceUnit -> ChartRequest a -> ChartOptions
mkChartOptions dunit request =
  MkChartOptions
    { title = request.title,
      yOptions,
      y1Options
    }
  where
    (yOptions, y1Options) = case request.y1Axis of
      Nothing ->
        let lbl = mkYLabel request.yAxis
            opts = MkYOptions lbl YLeft
         in (opts, Nothing)
      Just y1Axis ->
        let lbl = mkYLabel request.yAxis
            opts = MkYOptions lbl YLeft
            lbl1 = mkYLabel y1Axis
            opts1 = MkYOptions lbl1 YRight
         in (opts, Just opts1)

    mkYLabel :: YAxisType -> Text
    mkYLabel = \case
      YAxisDistance -> dstTxt
      YAxisDuration -> "time"
      YAxisPace -> "pace /" <> dstTxt
      where
        dstTxt = display dunit

-- | TODO: This can be replaced with -XNamedDefaults once it is available.
t :: Text -> Text
t = id

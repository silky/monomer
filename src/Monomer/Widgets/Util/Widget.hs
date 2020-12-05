{-# LANGUAGE FlexibleContexts #-}

module Monomer.Widgets.Util.Widget (
  pointInViewport,
  defaultWidgetNode,
  isWidgetVisible,
  isFocused,
  isHovered,
  widgetDataGet,
  widgetDataSet,
  resultWidget,
  resultEvts,
  resultReqs,
  resultReqsEvts,
  makeState,
  useState,
  instanceMatches,
  isTopLevel,
  handleFocusChange,
  resizeWidget,
  buildLocalMap,
  findWidgetByKey
) where

import Control.Lens ((&), (^#), (#~), (^.), (.~))
import Data.Default
import Data.Foldable (foldl')
import Data.Maybe
import Data.Map.Strict (Map)
import Data.Sequence (Seq)
import Data.Typeable (cast, Typeable)

import qualified Data.Map.Strict as M
import qualified Data.Sequence as Seq

import Monomer.Core
import Monomer.Event (checkKeyboard, isKeyC, isKeyV)
import Monomer.Graphics.Types

import qualified Monomer.Lens as L

pointInViewport :: Point -> WidgetNode s e -> Bool
pointInViewport p node = pointInRect p (node ^. L.widgetInstance . L.viewport)

defaultWidgetNode :: WidgetType -> Widget s e -> WidgetNode s e
defaultWidgetNode widgetType widget = WidgetNode {
  _wnWidget = widget,
  _wnWidgetInstance = def & L.widgetType .~ widgetType,
  _wnChildren = Seq.empty
}

isWidgetVisible :: WidgetNode s e -> Rect -> Bool
isWidgetVisible node vp = isVisible && isOverlapped where
  inst = node ^. L.widgetInstance
  isVisible = inst ^. L.visible
  isOverlapped = rectsOverlap vp (inst ^. L.viewport)

isFocused :: WidgetEnv s e -> WidgetNode s e -> Bool
isFocused wenv node = wenv ^. L.focusedPath == node ^. L.widgetInstance . L.path

isHovered :: WidgetEnv s e -> WidgetNode s e -> Bool
isHovered wenv node = validPos && isTopLevel wenv node where
  inst = node ^. L.widgetInstance
  viewport = inst ^. L.viewport
  mousePos = wenv ^. L.inputStatus . L.mousePos
  validPos = pointInRect mousePos viewport

widgetDataGet :: s -> WidgetData s a -> a
widgetDataGet _ (WidgetValue value) = value
widgetDataGet model (WidgetLens lens) = model ^# lens

widgetDataSet :: WidgetData s a -> a -> [WidgetRequest s]
widgetDataSet WidgetValue{} _ = []
widgetDataSet (WidgetLens lens) value = [UpdateModel updateFn] where
  updateFn model = model & lens #~ value

resultWidget :: WidgetNode s e -> WidgetResult s e
resultWidget node = WidgetResult node [] []

resultEvts :: WidgetNode s e -> [e] -> WidgetResult s e
resultEvts node events = result where
  result = WidgetResult node [] events

resultReqs :: WidgetNode s e -> [WidgetRequest s] -> WidgetResult s e
resultReqs node requests = result where
  result = WidgetResult node requests []

resultReqsEvts :: WidgetNode s e -> [WidgetRequest s] -> [e] -> WidgetResult s e
resultReqsEvts node requests events = result where
  result = WidgetResult node requests events

makeState :: Typeable i => i -> s -> Maybe WidgetState
makeState state model = Just (WidgetState state)

useState ::  Typeable i => Maybe WidgetState -> Maybe i
useState Nothing = Nothing
useState (Just (WidgetState state)) = cast state

instanceMatches :: WidgetNode s e -> WidgetNode s e -> Bool
instanceMatches newNode oldNode = typeMatches && keyMatches where
  oldInst = oldNode ^. L.widgetInstance
  newInst = newNode ^. L.widgetInstance
  typeMatches = oldInst ^. L.widgetType == newInst ^. L.widgetType
  keyMatches = oldInst ^. L.key == newInst ^. L.key

isTopLevel :: WidgetEnv s e -> WidgetNode s e -> Bool
isTopLevel wenv node = maybe inTopLayer isPrefix (wenv ^. L.overlayPath) where
  mousePos = wenv ^. L.inputStatus . L.mousePos
  inTopLayer = wenv ^. L.inTopLayer $ mousePos
  path = node ^. L.widgetInstance . L.path
  isPrefix parent = Seq.take (Seq.length parent) path == parent

handleFocusChange
  :: (c -> [e])
  -> (c -> [WidgetRequest s])
  -> c
  -> WidgetNode s e
  -> Maybe (WidgetResult s e)
handleFocusChange evtFn reqFn config node = result where
  evts = evtFn config
  reqs = reqFn config
  result
    | not (null evts && null reqs) = Just $ resultReqsEvts node reqs evts
    | otherwise = Nothing

resizeWidget
  :: WidgetEnv s e
  -> Rect
  -> Rect
  -> WidgetNode s e
  -> WidgetNode s e
resizeWidget wenv viewport renderArea widgetRoot = newRoot where
  sizeReq = widgetGetSizeReq (_wnWidget widgetRoot) wenv widgetRoot
  reqRoot = sizeReq ^. L.widget
    & L.widgetInstance . L.sizeReqW .~ sizeReq ^. L.sizeReqW
    & L.widgetInstance . L.sizeReqH .~ sizeReq ^. L.sizeReqH
  reqRootWidget = sizeReq ^. L.widget . L.widget

  newRoot = widgetResize reqRootWidget wenv viewport renderArea reqRoot

findWidgetByKey
  :: WidgetKey
  -> Map WidgetKey (WidgetNode s e)
  -> Maybe (WidgetNode s e)
findWidgetByKey key map = M.lookup key map

buildLocalMap :: Seq (WidgetNode s e) -> Map WidgetKey (WidgetNode s e)
buildLocalMap widgets = newMap where
  addWidget map widget
    | isJust key = M.insert (fromJust key) widget map
    | otherwise = map
    where
      key = widget ^. L.widgetInstance . L.key
  newMap = foldl' addWidget M.empty widgets

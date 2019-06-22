module Compile where

import qualified Closure  as C
import qualified Codegen  as Gen
import qualified Desugar  as D
import qualified Hoist    as H
import qualified Lazy     as L
import qualified Nameless as N
import qualified Parse    as P
import qualified Typing   as T

import Control.Exception
import Data.Text

compile :: P.Code -> IO Text
compile x = do
  () <- evaluate t
  ir <- Gen.toLLVM c
  return ir
  where
    e = N.nameless $ D.desugar x
    t = case T.typing e of
          Right t  -> t
          Left err -> error $ show err
    c = Gen.codegen $ H.hoist $ C.convert $ L.lazy e

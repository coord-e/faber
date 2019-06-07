module Desugar where

import qualified Parse as P
import qualified Operators as Op

data Expr
  = Integer Int
  | Lambda String Expr
  | Apply Expr Expr
  | Variable String
  | BinaryOp Op.BinaryOp Expr Expr
  | SingleOp Op.SingleOp Expr
  deriving (Show)

desugar_lambda :: [String] -> Expr -> Expr
desugar_lambda (x:xs) = Lambda x . desugar_lambda xs
desugar_lambda [] = id

desugar :: P.Expr -> Expr
desugar (P.Lambda ps body) = desugar_lambda ps $ desugar body
desugar (P.Integer i) = Integer i
desugar (P.Apply a b) = Apply (desugar a) (desugar b)
desugar (P.Variable x) = Variable x
desugar (P.BinaryOp op a b) = BinaryOp op (desugar a) (desugar b)
desugar (P.SingleOp op x) = SingleOp op $ desugar x
